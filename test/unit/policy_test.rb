require 'test_helper'

class PolicyTest < ActiveSupport::TestCase

  fixtures :all

  test "deep clone" do
    policy = policies(:download_for_all_sysmo_users_policy)

    copy = policy.deep_copy    
    assert_equal policy.sharing_scope,copy.sharing_scope
    assert_equal policy.access_type,copy.access_type
    assert_equal policy.name,copy.name
    assert_not_equal policy.id,copy.id

    assert policy.permissions.size>0,"needs to have custom permissions to make this test meaningful"
    assert copy.permissions.size>0,"needs to have custom permissions to make this test meaningful"

    assert_equal policy.permissions.size,copy.permissions.size

    policy.permissions.each_with_index do |perm,i|
      copy_perm = copy.permissions[i]
      assert_equal perm.contributor,copy_perm.contributor      
      assert_equal perm.access_type,copy_perm.access_type
      assert_not_equal perm.id,copy_perm.id      
    end
  end
  
  test "private policy" do
    pol=Policy.private_policy
    assert_equal Policy::PRIVATE, pol.sharing_scope
    assert_equal Policy::NO_ACCESS, pol.access_type
    assert_equal false,pol.use_whitelist
    assert_equal false,pol.use_blacklist
    assert pol.permissions.empty?
  end

  test "default policy" do
    with_config_value "is_virtualliver",false do
      pol=Policy.default
      assert_equal Policy::PRIVATE, pol.sharing_scope
      assert_equal Policy::NO_ACCESS, pol.access_type
      assert_equal false, pol.use_whitelist
      assert_equal false, pol.use_blacklist
      assert pol.permissions.empty?
    end
  end

  test "default policy for virtual liver" do
    with_config_value "is_virtualliver",true do
      pol=Policy.default
      assert_blank pol.sharing_scope
      assert_blank pol.access_type
      assert_equal false, pol.use_whitelist
      assert_equal false, pol.use_blacklist
      assert pol.permissions.empty?
    end
  end

  test "policy access type presedence" do
    assert Policy::NO_ACCESS < Policy::VISIBLE
    assert Policy::VISIBLE < Policy::ACCESSIBLE
    assert Policy::ACCESSIBLE < Policy::EDITING
    assert Policy::EDITING < Policy::MANAGING
  end

  test "policy sharing scope presedence" do
    assert Policy::PRIVATE < Policy::ALL_SYSMO_USERS
    assert Policy::ALL_SYSMO_USERS < Policy::EVERYONE
  end

  #Tests for preview permission
  #In a group, when a person can perform an item with different access_type, choose the highest access_type
  test "remove duplication by choosing the highest access_type" do
    #create a bundle of people array
    people_with_access_type = []
    i = 0
    access_type = 1
    while i<10
      people_with_access_type.push [i, 'name' + i.to_s, access_type ]
      i +=1
    end
    #create duplication
    i = 0
    access_type = 1
    while i<10
      people_with_access_type.push [i, 'name' + i.to_s, access_type ]
      i +=1
    end
    #create duplication but with different access_type
    i = 0
    max_access_type = 2
    while i<10
      people_with_access_type.push [i, 'name' + i.to_s, max_access_type ]
      i +=1
    end
    #remove duplication by choosing the highest access_type
    people_with_highest_access_type = Policy.new().remove_duplicate(people_with_access_type)

    assert_equal 10, people_with_highest_access_type.count
    people_with_highest_access_type.each do |person|
      assert_equal max_access_type, person[2]
    end
    #the array is unique
    assert_equal people_with_highest_access_type.uniq, people_with_highest_access_type
  end

  #if a person in 2 groups perform different access_type on an item, select the access_type of a group which has higher precedence
  test "should get access_type from the precedence group" do
    #create 2 groups with bundle of people, people from group 1 have random access_type, people from group 2 have fix access_type
    people_in_group1 = []
    people_in_group2 = []
    i = 0
    access_type = 2
    while i<10
      people_in_group1.push [i, 'name' + i.to_s, rand(4) ]
      people_in_group2.push [i, 'name' + i.to_s, access_type ]
      i +=1
    end
    #group 2 has higher precedence than group 1
    filtered_people = Policy.new().precedence(people_in_group1, people_in_group2)
    filtered_people.each do |person|
      assert_equal access_type, person[2]
    end
  end

  test'should add people who are in the whitelist' do
    #create bundle of people
    people_with_access_type = []
    i = 0
    while i<10
      people_with_access_type.push [i, 'name' + i.to_s, rand(4) + 1]
      i +=1
    end
    #create a whitelist
    whitelist = []
    i = 0
    while i<5
      random_id = rand(15)
      whitelist.push [random_id, 'name' + random_id.to_s, 2]
      i +=1
    end
    whitelist =  Policy.new().remove_duplicate(whitelist)
    whitelist_added= whitelist.select{|person| person[0]>9}
    filtered_people = Policy.new().add_people_in_whitelist(people_with_access_type, whitelist)
    assert_equal (people_with_access_type.count + whitelist_added.count), filtered_people.count
  end

  test 'should have asset managers in the summarize_permissions if the asset is entirely private' do
    asset_manager = Factory(:asset_manager)
    policy = Factory(:private_policy)
    User.with_current_user Factory(:user) do
      people_in_group = policy.summarize_permissions [], [asset_manager]
      assert people_in_group[Policy::MANAGING].include?([asset_manager.id, asset_manager.name+' (asset manager)',Policy::MANAGING])
    end
  end

  test 'should have asset managers in the summarize_permissions if the asset is not entirely private' do
    asset_manager = Factory(:asset_manager)

    #private policy but with permissions
    policy1 = Factory(:private_policy)
    permission =  Factory(:permission, :contributor => Factory(:person), :access_type => Policy::VISIBLE, :policy => policy1)
    assert !policy1.permissions.empty?

    #share within network
    policy2 = Factory(:all_sysmo_viewable_policy)

    User.with_current_user Factory(:user) do
      people_in_group = policy1.summarize_permissions [], [asset_manager]
      assert people_in_group[Policy::MANAGING].include?([asset_manager.id, asset_manager.name+' (asset manager)',Policy::MANAGING])

      people_in_group = policy2.summarize_permissions [], [asset_manager]
      assert people_in_group[Policy::MANAGING].include?([asset_manager.id, asset_manager.name+' (asset manager)',Policy::MANAGING])
    end
  end

  test 'should concat the roles of a person after name' do
    asset_manager = Factory(:asset_manager)
    creator = Factory(:person)
    policy = Factory(:public_policy)
    User.with_current_user Factory(:user) do
      people_in_group = policy.summarize_permissions [creator], [asset_manager]
      #creator
      people_in_group[Policy::EDITING].each do |person|
        if person[0] == creator.id
          assert person[1].include?('(creator)')
        else
          assert !person[1].include?('(creator)')
        end
      end
      people_in_group[Policy::MANAGING].each do |person|
        if person[0] == asset_manager.id
          assert person[1].include?('(asset manager)')
        else
          assert !person[1].include?('(asset manager)')
        end
      end
    end
  end

end
