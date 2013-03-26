module Seek #:nodoc:
  module Permissions #:nodoc:

    AUTHORIZATION_ACTIONS = [:view, :edit, :download, :delete, :manage]

    module ActsAsAuthorized
      def self.included(ar)
        ar.const_get(:Base).class_eval { include BaseExtensions }
        ar.module_eval { include AuthorizationEnforcement }
        ar.const_get(:Base).class_eval { does_not_require_can_edit :uuid, :first_letter }
      end

      module BaseExtensions
        def self.included base
          base.extend ClassMethods
        end

        #Sets up the basic interface for authorization hooks. All AR instances get these methods, and by default they return true.
        AUTHORIZATION_ACTIONS.each do |action|
          define_method "can_#{action}?" do
            true
          end

          def can_perform? action, *args
            send "can_#{action}?", *args
          end
        end

        def authorization_supported?
          self.class.authorization_supported?
        end

        def contributor_credited?
          false
        end

        def title_is_public?
          false
        end

        def publish!
          if can_publish?
            policy.access_type=Policy::ACCESSIBLE
            policy.sharing_scope=Policy::EVERYONE
            policy.save
            touch
          else
            false
          end
        end

        def is_published?
          if self.is_downloadable?
            can_download? nil
          else
            can_view? nil
          end
        end

        def can_send_publishing_request?(user=User.current_user)
          can_manage?(user) && ResourcePublishLog.last_waiting_approval_log(self,user).nil?
        end

        #the asset that can be published together with publishing the whole ISA
        def is_in_isa_publishable?
          #currently based upon the naive assumption that downloadable items are publishable, which is currently the case but may change.
          is_downloadable?
        end

        module ClassMethods
          def acts_as_authorized
            include Seek::Permissions::PolicyBasedAuthorization
            include Seek::Permissions::CodeBasedAuthorization
            include Seek::Permissions::StateBasedPermissions
          end

          def authorization_supported?
            include?(Seek::Permissions::PolicyBasedAuthorization)
          end
        end
      end
    end
  end
end

require 'seek/permissions/authorization_enforcement'
require 'seek/permissions/policy_based_authorization'
require 'seek/permissions/code_based_authorization'
require 'seek/permissions/state_based_permissions'

ActiveRecord.module_eval do
  include Seek::Permissions::ActsAsAuthorized
end
