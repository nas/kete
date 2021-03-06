class ImagesController < ApplicationController
  include ExtendedContentController

  def index
    redirect_to_search_for('StillImage')
  end

  def list
    index
  end

  def show
    prepare_item_variables_for("StillImage", true)
    @still_image = @item

    @view_size = params[:view_size] || "medium"
    @image_file = ImageFile.find_by_thumbnail_and_still_image_id(@view_size, params[:id])

    exclude = { :conditions => "user_portrait_relations.position != 1 AND user_portrait_relations.still_image_id != #{@still_image.id}" }
    @portraits_total_count = @still_image.creator.portraits.count(exclude)
    @viewer_portraits = @portraits_total_count > 0 ? @still_image.creator.portraits.all(exclude.merge(:limit => 12)) : nil

    respond_to do |format|
      format.html
      format.xml { render_oai_record_xml(:item => @still_image) }
    end
  end

  def new
    @still_image = StillImage.new
  end

  def create
    @still_image = StillImage.new
    # handle problems with image file first
    @image_file = ImageFile.new(params[:image_file].merge({ :file_private => params[:still_image][:file_private],
                                                            :item_private => params[:still_image][:private] }))

    @successful = @image_file.save

    if @successful

      @still_image = StillImage.new(params[:still_image])

      # if we are allowing harvesting of embedded metadata from the image_file
      # we need to grab it from the image_file's file path
      @still_image.populate_attributes_from_embedded_in(@image_file.full_filename) if ENABLE_EMBEDDED_SUPPORT

      @successful = @still_image.save

      if @successful
        # add this to the user's empire of creations
        # TODO: allow current_user whom is at least moderator to pick another user
        # as creator
        @still_image.creator = current_user

        @still_image.do_notifications_if_pending(1, current_user)

        @image_file.still_image_id = @still_image.id
        @image_file.save

        # Set the file privacy ahead of time so AttachmentFuOverload can find the value..# attachment_fu doesn't insert our still_image_id into the thumbnails
        # automagically
        @image_file.thumbnails.each do |thumb|
          thumb.still_image_id = @still_image.id
          thumb.save!
        end

        if params[:portrait]
          UserPortraitRelation.new_portrait_for(current_user, @still_image)
          if params[:selected_portrait]
            UserPortraitRelation.make_portrait_selected_for(current_user, @still_image)
          end
          expire_contributions_caches_for(current_user, :dont_rebuild_zoom => true)
        end
      end

      setup_related_topic_and_zoom_and_redirect(@still_image, nil, :private => (params[:still_image][:private] == "true"))
    else
      render :action => 'new'
    end
  end

  def edit
    @still_image = StillImage.find(params[:id])
    public_or_private_version_of(@still_image)
  end

  def update
    @still_image = StillImage.find(params[:id])

    version_after_update = @still_image.max_version + 1

    @successful = ensure_no_new_insecure_elements_in('still_image')
    @still_image.attributes = params[:still_image]
    @successful = @still_image.save if @successful

    if @successful
      # if they have uploaded something new, insert it
      @image_file = ImageFile.update_attributes(params[:image_file]) if !params[:image_file][:uploaded_data].blank?

      after_successful_zoom_item_update(@still_image, version_after_update)
      flash[:notice] = 'Image was successfully updated.'
      redirect_to_show_for(@still_image, :private => (params[:still_image][:private] == "true"))
    else
      render :action => 'edit'
    end
  end

  def destroy
    zoom_destroy_and_redirect('StillImage','Image')
  end
end
