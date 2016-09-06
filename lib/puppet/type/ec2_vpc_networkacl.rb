require_relative '../../puppet_x/puppetlabs/property/tag.rb'

Puppet::Type.newtype(:ec2_vpc_networkacl) do
  @doc = 'Type representing a Network Access Control List.'

  ensurable

  newparam(:name, namevar: true) do
    desc 'The name of the ACL.'
    validate do |value|
      fail 'ACLs must have a name' if value == ''
      fail 'name should be a String' unless value.is_a?(String)
    end
  end

  newproperty(:region) do
    desc 'the region in which to launch the ACL'
    validate do |value|
      fail 'region should not contain spaces' if value =~ /\s/
      fail 'region should be a String' unless value.is_a?(String)
    end
  end

  newproperty(:vpc) do
    desc 'The VPC to attach the ACL to.'
    validate do |value|
      fail 'vpc should be a String' unless value.is_a?(String)
    end
  end

  newparam(:default) do
    desc 'Is the ACL the default for the VPC.'
    defaultto :false
    newvalues(:true, :'false')
    def insync?(is)
      is.to_s == should.to_s
    end
  end

  newproperty(:tags, :parent => PuppetX::Property::AwsTag) do
    desc 'Tags to assign to the subnet.'
  end


  autorequire(:ec2_vpc) do
    self[:vpc]
  end

end
