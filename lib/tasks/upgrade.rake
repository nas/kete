# lib/tasks/upgrade.rake
#
# mainly checks that the system settings we need for the new code
# are in the db, if not adds them to db
#
# Walter McGinnis, 2008-01-15
#
namespace :kete do
  desc "Do everything that we need done, like adding data to the db, for an upgrade."
  task :upgrade => ['kete:upgrade:add_new_baskets',
                    'kete:upgrade:add_tech_admin',
                    'kete:upgrade:add_new_system_settings',
                    'kete:upgrade:add_new_default_topics',
                    'kete:upgrade:change_zebra_password',
                    'kete:upgrade:check_required_software',
                    'kete:upgrade:add_missing_mime_types',
                    'kete:upgrade:correct_basket_defaults',
                    'kete:upgrade:expire_depreciated_rss_cache',
                    'kete:upgrade:set_default_join_and_memberlist_policies',
                    'kete:upgrade:make_baskets_approved_if_status_null',
                    'kete:upgrade:ignore_default_baskets_if_setting_not_set',
                    'zebra:load_initial_records',
                    'kete:upgrade:update_existing_comments_commentable_private',
                    'kete:tools:remove_robots_txt',
                    'kete:upgrade:ensure_logins_all_valid',
                    'kete:upgrade:move_user_name_to_display_and_resolved_name']
  namespace :upgrade do
    desc 'Privacy Controls require that Comment#commentable_private be set.  Update existing comments to have this data.'
    task :update_existing_comments_commentable_private => :environment do
      comment_count = 0
      Comment.find(:all, :conditions => "commentable_private is null").each do |comment|
        comment.commentable_private = false if comment.commentable_private.blank?
        comment.save!
        comment_count += 1
      end
      p "updated " + comment_count.to_s + " existing comments that didn't have privacy set."
    end

    desc 'Add the new system settings that are missing from our system.'
    task :add_new_system_settings => :environment do
      system_settings_from_yml = YAML.load_file("#{RAILS_ROOT}/db/bootstrap/system_settings.yml")

      # for each system_setting from yml
      # check if it's in the db
      # if not, add it
      # system settings have unique names
      system_settings_from_yml.each do |setting_array|
        setting_hash = setting_array[1]

        # if there are existing system settings
        # drop id from hash, as we want to determine it dynamically
        # else we want to use the bootstap versions
        setting_hash.delete('id') if SystemSetting.count > 0

        if !SystemSetting.find_by_name(setting_hash['name'])
          SystemSetting.create!(setting_hash)
          p "added " + setting_hash['name']
        end
      end
    end

    desc 'Add the new default topics that are missing from our Kete installation.'
    task :add_new_default_topics => :environment do
      topics_from_yml = YAML.load_file("#{RAILS_ROOT}/db/bootstrap/topics.yml")

      # support for legacy kete installations where basket ids
      # are different from those in topics.yml
      # NOTE: if this gets uses again in another task, move this to a reusable method of its own
      basket_ids = { "1" => 1,
                     "2" => HELP_BASKET,
                     "3" => ABOUT_BASKET,
                     "4" => DOCUMENTATION_BASKET }

      # for each topic from yml
      topics_from_yml.each do |topic_array|
        topic_hash = topic_array[1]

        # if there are existing topics
        # drop id from hash, as we want to determine it dynamically
        # else we want to use the bootstap versions
        topic_hash.delete('id') if Topic.count > 0

        # map basket id to Kete's basket id (support for legacy installations)
        topic_hash['basket_id'] = basket_ids[topic_hash['basket_id'].to_s]

        # check if it's in the db by looking for a similar topic title in
        # the basket the topic is intended for, and if not present, add it
        if !Topic.find_by_title_and_basket_id(topic_hash['title'], topic_hash['basket_id'])
          topic = Topic.create!(topic_hash)
          topic.creator = User.first
          topic.save!
          p "added topic: " + topic_hash['title']
        end
      end
    end

    desc 'Add any new default baskets that are missing from our system.'
    task :add_new_baskets => :environment do
      baskets_from_yml = YAML.load_file("#{RAILS_ROOT}/db/bootstrap/baskets.yml")
      # For each basket from yml
      # check if it's in the db
      # if not, add it
      # system settings have unique names
      admin_user = User.find(1)
      baskets_from_yml.each do |basket_array|
        basket_hash = basket_array[1]

        # drop id from hash, as we want to determine it dynamically
        basket_hash.delete('id')

        if !Basket.find_by_name(basket_hash['name'])
          basket = Basket.create!(basket_hash)
          basket.accepts_role('admin', admin_user)
          p "added " + basket_hash['name']
        end
      end
    end

    desc 'Add tech_admin role if it is missing from our system.'
    task :add_tech_admin => :environment do
      roles_from_yml = YAML.load_file("#{RAILS_ROOT}/db/bootstrap/roles.yml")

      admin_user = User.find(1)
      tech_admin_hash = roles_from_yml['tech_admin']
      if !Role.find_by_name('tech_admin')
        Role.create!(tech_admin_hash)
        admin_user.has_role('tech_admin', Basket.find(1))
        p "added " + tech_admin_hash['name']
      end
    end

    desc 'Change zebra password file to use clear text since encrypted is broken.'
    task :change_zebra_password => :environment do
      ENV['ZEBRA_PASSWORD'] = ZoomDb.find(1).zoom_password
      Rake::Task['zebra:stop'].invoke
      Rake::Task['zebra:set_keteaccess'].invoke
      Rake::Task['zebra:start'].invoke
      p "changed zebra password file"
    end

    desc 'This checks for missing required software and installs it if possible.'
    task :check_required_software => :environment do
      include RequiredSoftware
      required_software = load_required_software
      missing_software = { 'Gems' => missing_libs(required_software), 'Commands' => missing_commands(required_software)}
      p "you have the following missing gems (you might want to do rake prep_app first): #{missing_software['Gems'].inspect}" if !missing_software['Gems'].blank?
      p "you have the following missing external software (take steps to install them before starting your kete server): #{missing_software['Commands'].inspect}" if !missing_software['Commands'].blank?
    end

    desc 'Fix the default baskets settings for unedited baskets so they inherit (like they were intended to)'
    task :correct_basket_defaults => :environment do
      Basket.all.each do |basket|
        next unless Basket.standard_baskets.include?(basket.id)
        next unless basket.created_at == basket.updated_at

        correctable_fields = ['private_default', 'file_private_default', 'allow_non_member_comments', 'show_privacy_controls']
        current_basket_defaults = correctable_fields.map { |field| basket.send(field) }
        if basket.id == 1 # site basket
          standard_basket_defaults = [false, false, true, false]
        else # other default baskets
          standard_basket_defaults = [nil, nil, nil, nil]
        end

        next if current_basket_defaults == standard_basket_defaults

        correctable_fields.each_with_index do |field, index|
          basket.send(field+"=", standard_basket_defaults[index])
        end
        # make sure we set 'do_not_sanitize' to true or save will fail if the basket has html
        basket.do_not_sanitize = true
        basket.save!
        p "Corrected settings of #{basket.name} basket"
      end
    end

    desc 'Make Site basket have membership requests closed, and member list visibility at least admin.'
    task :set_default_join_and_memberlist_policies => :environment do
      # set some defaults in the site basket
      site_basket = Basket.first # site
      site_basket.settings[:basket_join_policy] = 'closed' if site_basket.settings[:basket_join_policy].class == NilClass
      site_basket.settings[:memberlist_policy] = 'at least admin' if site_basket.settings[:memberlist_policy].class == NilClass
      # if the about, help, or documentation baskets are nil, fill in the same value as the site basket
      Basket.about_basket.settings[:basket_join_policy] = site_basket.settings[:basket_join_policy] if Basket.about_basket.settings[:basket_join_policy].class == NilClass
      Basket.help_basket.settings[:basket_join_policy] = site_basket.settings[:basket_join_policy] if Basket.help_basket.settings[:basket_join_policy].class == NilClass
      Basket.documentation_basket.settings[:basket_join_policy] = site_basket.settings[:basket_join_policy] if Basket.documentation_basket.settings[:basket_join_policy].class == NilClass
    end

    desc 'Make all baskets with the status of NULL set to approved'
    task :make_baskets_approved_if_status_null => :environment do
      Basket.all.each do |basket|
        # make sure we set 'do_not_sanitize' to true or update will fail if the basket has html
        basket.update_attributes!({ :status => 'approved',
                                    :creator_id => 1,
                                    :do_not_sanitize => true }) if basket.status.blank?
      end
    end

    desc 'Make about, documentation, and help baskets ignore on the site basket recent topics if not done yet.'
    task :ignore_default_baskets_if_setting_not_set => :environment do
      Basket.find_all_by_urlified_name(['about', 'documentation', 'help']).each do |basket|
        if basket.settings[:disable_site_recent_topics_display].class == NilClass
          basket.settings[:disable_site_recent_topics_display] = true
        end
      end
    end

    desc 'Ensure logins are valid before continuing (1.1 allowed spaces, 1.2 onwards does not).'
    task :ensure_logins_all_valid => :environment do
      users = User.all.collect { |user| (user.login =~ /\s/) ? user : nil }.compact.flatten
      users.each do |user|
        user.update_attributes!({ :login => user.login.gsub(/\s/, '_') })
        UserNotifier.deliver_login_changed(user)
        p "Altered login of #{user.user_name}#{" (#{user.login})" if user.login != user.user_name}."
        # we should clear the contribution caches but we don't have access to this method here
        #   expire_contributions_caches_for(user)
      end
    end

    desc 'Transfer the old user names in the extended content fields into the display/resolved name fields on the users table, and remove the user name field mapping for Users'
    task :move_user_name_to_display_and_resolved_name => :environment do
      user_count = 0
      already_set_resolved_name = false
      User.find(:all, :conditions => { :resolved_name => '' }).each do |user|
        already_set_resolved_name = true unless user.resolved_name.blank?

        unless already_set_resolved_name

          unless user.display_name.nil?
            user_name_field = EXTENDED_FIELD_FOR_USER_NAME
            extended_content_hash = user.xml_attributes_without_position
            if !extended_content_hash.blank? && !extended_content_hash[user_name_field].blank? && !extended_content_hash[user_name_field]['value'].blank?
              user.display_name = extended_content_hash[user_name_field]['value'].strip
              extended_content_hash = extended_content_hash.delete(user_name_field)
              user.extended_content_values = extended_content_hash
            end
          end
          user.resolved_name = user.login # this will get rewritten using an before save callback on the User model
          user.save!
          user_count += 1
        end
      end
      # finally, lets removing the user name field mapping to prevent new user names from being set
      content_type_id = ContentType.find_by_class_name('User').id
      extended_field_id = ExtendedField.find_by_label('User Name').id
      content_mapping = ContentTypeToFieldMapping.find_by_content_type_id_and_extended_field_id(content_type_id, extended_field_id)
      content_mapping.destroy unless content_mapping.nil?
      p "#{user_count.to_s} users user_name moved to resolved_name" if user_count > 0
    end

    desc 'Expire old style page caching for RSS feeds, otherwise they will conflict with new RSS caching system.'
    task :expire_depreciated_rss_cache => :environment do
      # needed for zoom_class_controller method
      include ZoomControllerHelpers

      # this is overkill do fully every time upgrade
      # so check if the basket has been previously cached under public
      Basket.find(:all).each do |basket|
        path = RAILS_ROOT + '/public/' + basket.urlified_name
        if File.directory?(path)
          ZOOM_CLASSES.each do |zoom_class|
            # here's the hack way
            # we know RSS feed caches live under "all" or "for" directories
            # actually, just "all" most likely, but taking no chances
            ['all', 'for'].each do |subdir|
              full_path = path + '/'+ subdir + '/' + zoom_class_controller(zoom_class)
              next unless File.directory?(full_path)
              # empty the directory files and then delete it
              Dir.glob("#{full_path}/*") do |file|
                File.delete(file)
              end
              Dir.rmdir(full_path)
            end

            # and here's the right way to do it
            # but i was getting this error:
            # private method `chomp' called for #<Hash:0x3e4e744>
            # /Users/walter/Development/apps/kete/vendor/rails/actionpack/lib/action_controller/caching/pages.rb:102:in `page_cache_file'
            # ApplicationController.expire_page(:controller => 'search',
            #                                               :action => 'rss',
            #                                               :urlified_name => basket.urlified_name,
            #                                               :controller_name_for_zoom_class => zoom_class_controller(zoom_class))
          end
          # finally delete the unneeded all and for directories
          ['all', 'for'].each do |subdir|
            full_path = path + '/' + subdir
            next unless File.directory?(full_path)
            Dir.rmdir(full_path)
          end
        end
      end
    end

    desc 'Checks for mimetypes an adds them if needed.'
    task :add_missing_mime_types => ['kete:upgrade:add_octet_stream_and_word_types',
                                     'kete:upgrade:add_excel_variants_to_documents',
                                     'kete:upgrade:add_aiff_to_audio_recordings',
                                     'kete:upgrade:add_tar_to_documents',
                                     'kete:upgrade:add_open_office_document_types',
                                     'kete:upgrade:add_jpegs_to_documents',
                                     'kete:upgrade:add_bmp_to_images',
                                     'kete:upgrade:add_eps_to_images',
                                     'kete:upgrade:add_file_mime_type_variants']

    desc 'Adds excel variants if needed'
    task :add_excel_variants_to_documents => :environment do
      setting = SystemSetting.find_by_name('Document Content Types')
      ['application/excel', 'application/x-excel', 'application/x-msexcel'].each do |new_type|
        if setting.push(new_type)
          p "added #{new_type} mime type to " + setting.name
        end
      end
    end

    desc 'Adds application/octet-stream and application/word if needed'
    task :add_octet_stream_and_word_types => :environment do
      ['Document Content Types', 'Video Content Types', 'Audio Content Types'].each do |setting_name|
        setting = SystemSetting.find_by_name(setting_name)
        if setting.push('application/octet-stream')
          p "added octet stream mime type to " + setting_name
        end
        if setting_name == 'Document Content Types'
          if setting.push('application/word')
            p "added application/word mime type to " + setting_name
          end
        end
      end
    end

    desc 'Adds application/x-tar if needed'
    task :add_tar_to_documents => :environment do
      setting = SystemSetting.find_by_name('Document Content Types')
      if setting.push('application/x-tar')
        p "added application/x-tar mime type to " + setting.name
      end
    end

    desc 'Adds jpeg types to documents if needed.  A lot of archive and repository sites call scans to jpeg of a historical document pages.'
    task :add_jpegs_to_documents => :environment do
      setting = SystemSetting.find_by_name('Document Content Types')
      ['image/jpeg', 'image/jpg'].each do |type|
        if setting.push(type)
          p "added #{type} mime type to " + setting.name
        end
      end
    end

    desc 'Adds audio/x-aiff if needed'
    task :add_aiff_to_audio_recordings => :environment do
      setting = SystemSetting.find_by_name('Audio Content Types')
      if setting.push('audio/x-aiff')
        p "added audio/x-aiff mime type to " + setting.name
      end
    end

    desc 'Adds image/bmp if needed to images'
    task :add_bmp_to_images => :environment do
      setting = SystemSetting.find_by_name('Image Content Types')
      if setting.push('image/bmp')
        p "added image/bmp mime type to " + setting.name
      end
    end

    desc 'Adds eps (application/postscript) if needed to images'
    task :add_eps_to_images => :environment do
      setting = SystemSetting.find_by_name('Image Content Types')
      if setting.push('application/postscript')
        p "added eps (application/postscript) mime type to " + setting.name
      end
    end

    desc 'Adds OpenOffice document types if needed'
    task :add_open_office_document_types => :environment do
      oo_types = ['application/vnd.oasis.opendocument.chart',
                  'application/vnd.oasis.opendocument.database',
                  'application/vnd.oasis.opendocument.formula',
                  'application/vnd.oasis.opendocument.drawing',
                  'application/vnd.oasis.opendocument.image',
                  'application/vnd.oasis.opendocument.text-master',
                  'application/vnd.oasis.opendocument.presentation',
                  'application/vnd.oasis.opendocument.spreadsheet',
                  'application/vnd.oasis.opendocument.text',
                  'application/vnd.oasis.opendocument.text-web']

      setting = SystemSetting.find_by_name('Document Content Types')
      oo_types.each do |type|
        if setting.push(type)
          p "added #{type} mime type to " + setting.name
        end
      end
    end

    desc 'Adds File mime type variants'
    task :add_file_mime_type_variants => :environment do
      new_mime_types =  [
                          [ 'Image Content Types',    [ 'image/quicktime', 'image/x-quicktime', 'image/x-ms-bmp' ] ],
                          [ 'Document Content Types', [ 'application/x-zip', 'application/x-zip-compressed', 'application/x-compressed-tar' ] ],
                          [ 'Video Content Types',    [ 'application/flash-video', 'application/x-flash-video', 'video/x-flv', 'video/mp4', 'video/x-m4v' ] ],
                          [ 'Audio Content Types',    [ 'audio/mpg', 'audio/x-mpeg', 'audio/wav', 'audio/x-vorbis+ogg' ] ]
                        ]
      new_mime_types.each do |settings|
        setting = SystemSetting.find_by_name(settings.first)
        settings.last.each do |type|
          if setting.push(type)
            p "added #{type} mime type to " + setting.name
          end
        end
      end
    end

  end
end
