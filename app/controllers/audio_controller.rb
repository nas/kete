class AudioController < ApplicationController
  include ExtendedContentController

  # GETs should be safe (see http://www.w3.org/2001/tag/doc/whenToUseGet.html)
  verify :method => :post, :only => [ :destroy, :create, :update ],
         :redirect_to => { :action => :list }

  def index
    redirect_to_search_for('AudioRecording')
  end

  def list
    index
  end

  def show
    if !has_all_fragments? or params[:format] == 'xml'
      @audio_recording = @current_basket.audio_recordings.find(params[:id])
      @title = @audio_recording.title
    end

    if !has_fragment?({:part => 'contributions' }) or params[:format] == 'xml'
      @creator = @audio_recording.creators.first
      @last_contributor = @audio_recording.contributors.last || @creator
    end

    if !has_fragment?({:part => 'comments' }) or params[:format] == 'xml'
      @comments = @audio_recording.comments
    end

    respond_to do |format|
      format.html
      format.xml { render_oai_record_xml(:item => @audio_recording) }
    end
  end

  def new
    @audio_recording = AudioRecording.new
  end

  def create
    @audio_recording = AudioRecording.new(extended_fields_and_params_hash_prepare(:content_type => @content_type, :item_key => 'audio_recording', :item_class => 'AudioRecording'))

    @successful = @audio_recording.save

    # add this to the user's empire of creations
    # TODO: allow current_user whom is at least moderator to pick another user
    # as creator
    @audio_recording.creators << current_user

    setup_related_topic_and_zoom_and_redirect(@audio_recording)
  end

  def edit
    @audio_recording = AudioRecording.find(params[:id])
  end

  def update
    @audio_recording = AudioRecording.find(params[:id])

    if @audio_recording.update_attributes(extended_fields_and_params_hash_prepare(:content_type => @content_type, :item_key => 'audio_recording', :item_class => 'AudioRecording'))
      # add this to the user's empire of contributions
      # TODO: allow current_user whom is at least moderator to pick another user
      # as contributor
      # uses virtual attr as hack to pass version to << method
      @current_user = current_user
      @current_user.version = @audio_recording.version
      @audio_recording.contributors << @current_user

      prepare_and_save_to_zoom(@audio_recording)

      flash[:notice] = 'AudioRecording was successfully updated.'
      redirect_to :action => 'show', :id => @audio_recording
    else
      render :action => 'edit'
    end
  end

  def destroy
    zoom_destroy_and_redirect('AudioRecording','Audio recording')
  end

  private
  def load_content_type
    @content_type = ContentType.find_by_class_name('AudioRecording')
  end
end
