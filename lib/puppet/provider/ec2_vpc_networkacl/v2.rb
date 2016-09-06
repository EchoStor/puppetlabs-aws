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

  read_only(:vpc, :region, :default, :entries)

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
            'action' => entry.rule_action,
            'number' => entry.rule_number,
        }
        entries << config
      end
    end
    entries.flatten.uniq.compact
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
    response = ec2.create_network_acl(
      vpc_id: vpc_response.data.vpcs.first.vpc_id,
    )
    acl_id = response.data.network_acl.network_acl_id
    with_retries(:max_tries => 5) do
      ec2.create_tags(
        resources: [acl_id],
        tags: tags_for_resource,
      )
    end

    @property_hash[:ensure] = :present
  end

  def destroy
    Puppet.info("Deleting subnet #{name} in #{target_region}")
    ec2_client(target_region).delete_subnet(
      subnet_id: @property_hash[:id]
    )
    @property_hash[:ensure] = :absent
  end
end
