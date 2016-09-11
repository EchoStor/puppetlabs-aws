require_relative '../../../puppet_x/puppetlabs/aws.rb'

Puppet::Type.type(:ec2_vpc_networkacl).provide(:v2, :parent => PuppetX::Puppetlabs::Aws) do
  confine feature: :aws
  confine feature: :retries

  mk_resource_methods
  remove_method :tags=

  def self.instances
    regions.collect do |region|
      begin
        response = ec2_client(region).describe_network_acls()
        acls = []
        response.data.network_acls.each do |acl|
          hash = acl_to_hash(region, acl)
          acls << new(hash) if has_name?(hash)
        end
        acls
      rescue Timeout::Error, StandardError => e
        raise PuppetX::Puppetlabs::FetchingAWSDataError.new(region, self.resource_type.name.to_s, e.message)
      end
    end.flatten
  end

  read_only(:vpc, :region, :default, :associations, :entries)

  def self.prefetch(resources)
    instances.each do |prov|
      if resource = resources[prov.name] # rubocop:disable Lint/AssignmentInCondition
        resource.provider = prov if resource[:region] == prov.region
      end
    end
  end

  def self.format_entries(acl)
    entries = []
    acl[:entries].each do |entry|
      if entry.rule_number < 32767
        config = {
            'cidr_block' => entry.cidr_block,
            'egress' => entry.egress,
            'rule_action' => entry.rule_action,
            'rule_number' => entry.rule_number,
        }
        entries << config
      end
    end
    entries.flatten.uniq.compact
  end

  def self.format_association(acl,region)
      associations = []
      acl[:associations].each do |association|
        response = ec2_client(region).describe_subnets(subnet_ids: [association.subnet_id])
        subnet_names = response.data.subnets.collect do |subnet|
          subnet_name_tag = subnet.tags.detect {|tag| tag.key == 'Name'}
          associations << subnet_name_tag.value
        end
      end
      associations.flatten.uniq.compact
  end

  def self.acl_to_hash(region, acl)
    name = name_from_tag(acl)
    return {} unless name

    {
      name: name,
      id: acl.network_acl_id,
      vpc: vpc_name_from_id(region, acl.vpc_id),
      ensure: :present,
      region: region,
      default: acl.is_default,
      tags: tags_for(acl),
      entries: format_entries(acl),
      associations: format_association(acl,region),
    }
  end

  def exists?
    Puppet.debug("Checking if Network ACL #{name} exists in #{target_region}")
    @property_hash[:ensure] == :present
  end

  def create
    Puppet.info("Creating Network ACL #{name} in #{target_region}")
    ec2 = ec2_client(target_region)
    vpc_response = ec2.describe_vpcs(filters: [
      {name: "tag:Name", values: [resource[:vpc]]},
    ])
    fail("Multiple VPCs with name #{resource[:vpc]}") if vpc_response.data.vpcs.count > 1
    fail("No VPCs with name #{resource[:vpc]}") if vpc_response.data.vpcs.empty?
    vpc_id = vpc_response.data.vpcs.first.vpc_id
    response = ec2.create_network_acl(
      vpc_id: vpc_id,
    )
    acl_id = response.data.network_acl.network_acl_id

    with_retries(:max_tries => 5) do
      Puppet.debug(tags_for_resource)
      ec2.create_tags(
        resources: [acl_id],
        tags: tags_for_resource,
      )
    end

    unless resource[:entries].empty?
      create_entries(resource[:entries], acl_id)
    end
    unless resource[:associations].empty?
      associate_subnets(resource[:associations],vpc_id,acl_id)
    end

    @property_hash[:ensure] = :present
  end

  def create_entries(entries, acl_id)
    ec2 = ec2_client(target_region)
    entries.each do |entry|
      rule = {}
      rule[:network_acl_id] = acl_id
      rule[:protocol] = '-1'
      entry.each{|k,v| rule[k.to_sym] = v}
      Puppet.debug(rule.to_s)
      ec2.create_network_acl_entry(rule)
    end
  end

  def associate_subnets(subs, vpc_id, acl_id)
  ec2 = ec2_client(target_region)
  subnet_response = ec2.describe_subnets(filters:
    [{name: 'tag:Name', values: subs},{name: 'vpc-id',values: [vpc_id]}])
  fail("No subnets found") if subnet_response.data.subnets.empty?
  subnet_ids = []
  subnet_response.subnets.each do |subnet|
    subnet_ids <<  subnet.subnet_id
  end
  Puppet.info(subnet_ids)

  acl_response = ec2.describe_network_acls(filters:
    [{name: 'association.subnet-id', values: subnet_ids},{name: 'vpc-id',values: [vpc_id]}])
  acl_response.network_acls.each do |acl|
    acl.associations.each do |association|
      if association.network_acl_id != acl_id and subnet_ids.include? association.subnet_id
        ec2.replace_network_acl_association({
          association_id: association.network_acl_association_id,
          network_acl_id: acl_id})
      end
    end
  end
end

  def destroy
    Puppet.info("Deleting ACL #{name} in #{target_region}")
    ec2_client(target_region).delete_network_acl(
      network_acl_id: @property_hash[:id]
    )
    @property_hash[:ensure] = :absent
  end
end
