module AssetsCommonExtension
  include Seek::MimeTypes

  def show_via_url asset, content_blob=nil
    content_blob = content_blob.nil? ? asset.content_blob : content_blob
    code = url_response_code(content_blob.url)
    if (["302", "401"].include?(code))
      redirect_to(content_blob.url, :target=>"_blank")
    elsif code=="404"
      flash[:error]="This item is referenced at a remote location, which is currently unavailable"
      redirect_to polymorphic_path(asset.parent, {:version=>asset.version})
    else
      downloader=Seek::RemoteDownloader.new
      data_hash = downloader.get_remote_data content_blob.url
      send_file data_hash[:data_tmp_path], :filename => data_hash[:filename] || content_blob.original_filename, :content_type => data_hash[:content_type] || content_blob.content_type, :disposition => 'inline'
    end
  end

  def calculate_params symbol
    i = 0
    local_set = []
    url_set = []
    original_filename_from_url_set = []
    while !params[symbol].blank?
      if !params[symbol]['file_'+i.to_s].nil?
        if params[symbol]['file_'+i.to_s] != ""
          local_set << params[symbol]['file_'+i.to_s]
        end
        params[symbol].delete 'file_'+i.to_s
      end
      if !params[symbol]['url_'+i.to_s].nil?
        if params[symbol]['url_'+i.to_s] != ""
          url_set << params[symbol]['url_'+i.to_s]
        end
        params[symbol].delete 'url_'+i.to_s
      end
      if !params[symbol]['original_filename_'+i.to_s].nil?
        if params[symbol]['original_filename_'+i.to_s] != ""
          original_filename_from_url_set << params[symbol]['original_filename_'+i.to_s]
        end
        params[symbol].delete 'original_filename_'+i.to_s
      end
      i += 1
    end

    return [local_set, url_set, original_filename_from_url_set]
  end

  def retained_content_blob_ids
    if params[:content_blobs] && params[:content_blobs][:id]
      params[:content_blobs][:id].keys.collect{|id| id.to_i}
    else
      []
    end
  end


  def handle_batch_data render_action_on_error=:new
    #FIXME: too many nested if,else and rescue blocks. This method needs refactoring.
    c = self.controller_name.downcase
    @content_types = []
    @original_filenames = []
    @tmp_io_objects_localfile = []
    @tmp_io_objects_url = []
    @data_urls = []
    symb = c.singularize.to_sym
    object = eval("@#{c.singularize}")
    params_files = calculate_params(:content_blob)
    params_data = params_files.first
    params_url = params_files.second
    params_original_filename_from_ulr = params_files.third
    params_image_file = params[controller_name.singularize+'_image'].nil? ? nil : params[controller_name.singularize+'_image']['image_file']
    #ids of selected content_blobs of previous version, when uploading new version
    @retained_content_blob_ids = retained_content_blob_ids

    if render_action_on_error==:new || render_action_on_error.nil?
      params_files = params_data + params_url
    elsif render_action_on_error==:edit
      params_files = object.content_blobs
    end
    if params_files.blank? && params_image_file.blank? && @retained_content_blob_ids.blank?
      flash.now[:error] = "Please select at least a file/image to upload or provide a URL to the data."
      if render_action_on_error
        init_asset_for_render params
        respond_to do |format|
          format.html do
            render :action => render_action_on_error
          end
        end
      end
      return false
    elsif !params_data.blank? && !params_data.detect { |data| data.size == 0 }.nil? && params_url.blank?
      flash.now[:error] = "At least one file that you are uploading is empty. Please check your selection and try again!"
      if render_action_on_error
        init_asset_for_render params
        respond_to do |format|
          format.html do
            render :action => render_action_on_error
          end
        end
      end
      return false
    else
      #upload takes precedence if both params are present
      begin
        if !params_data.blank?
          # store properties and contents of the file temporarily and remove the latter from params[],
          # so that when saving main object params[] wouldn't contain the binary data anymore
          @content_types = params_data.collect(&:content_type)
          @original_filenames = params_data.collect(&:original_filename)
          @tmp_io_objects_localfile = params_data
        end
        if !params_url.blank?

          make_local_copy = (params[symb][:local_copy]=="1")
          @data_urls=params_url

          @data_urls.each_with_index do |data_url,index|

            code = url_response_code data_url
            if (code == "200")
              downloader=Seek::RemoteDownloader.new
              data_hash = downloader.get_remote_data data_url, nil, nil, nil, make_local_copy

              @tmp_io_objects_url << File.open(data_hash[:data_tmp_path], "r") if make_local_copy

              @content_types << data_hash[:content_type]
              @original_filenames << (params_original_filename_from_ulr[index] || data_hash[:filename])
            elsif (["302", "401"].include?(code))
              @tmp_io_objects_url << ""
              @content_types << ""
              @original_filenames << ""
            else
              flash.now[:error] = "Processing the URL responded with a response code (#{code}), indicating the <a href= \'#{data_url}\'>URL</a>  is inaccessible."
              if render_action_on_error
                init_asset_for_render params
                respond_to do |format|
                  format.html do
                    render :action => render_action_on_error
                  end
                end
              end
              return false
            end
          end
        end
      rescue Seek::IncompatibleProtocolException=>e
        flash.now[:error] = e.message
        if render_action_on_error
          init_asset_for_render params
          respond_to do |format|
            format.html do
              render :action => render_action_on_error
            end
          end
        end
        return false
      rescue Exception=>e
        flash.now[:error] = "Unable to read from the URL."
        flash.now[:error] <<   e.message
        if render_action_on_error
          init_asset_for_render params
          respond_to do |format|
            format.html do
              render :action => render_action_on_error
            end
          end
        end
        return false
      end
      params[symb].delete 'data_url'
      params[symb].delete 'data'
      params[symb].delete 'local_copy'
      return true
    end
  end

  def create_content_blobs
    asset = eval "@#{self.controller_name.downcase.singularize}"
    sym = self.controller_name.downcase.singularize.to_sym
    version = asset.version
    if asset.respond_to?(:content_blob) and !asset.respond_to?(:content_blobs)
      #if request is sent from a browser running on window, take the content type from the filename instead
      if request.headers['HTTP_USER_AGENT'].include?('Win')
        content_type = content_type_from_filename params[sym][:original_filename]
      else
        content_type = params[sym][:content_type]
      end
      # create new /new version
      asset.create_content_blob(:tmp_io_object => @tmp_io_object,
                                :url=>@data_url,
                                :original_filename=>params[sym][:original_filename],
                                :content_type=>content_type,
                                :asset_version=>version
      )

    elsif asset.respond_to? :content_blobs
      # create new /new version
      @tmp_io_objects_localfile.each do |tmp_io_object|
        #if request is sent from a browser running on window, take the content type from the filename instead
        if request.headers['HTTP_USER_AGENT'].include?('Win')
          content_type = content_type_from_filename @original_filenames[0]
        else
          content_type = @content_types[0].to_s
        end
        asset.content_blobs.create(:tmp_io_object => tmp_io_object,
                                   :original_filename=>@original_filenames[0],
                                   :content_type=>content_type,
                                   :asset_version=>version)
        @original_filenames.delete_at(0)
        @content_types.delete_at(0)
      end

      @data_urls.each_with_index do |data_url, index|
        asset.content_blobs.create(:tmp_io_object => @tmp_io_objects_url[index],
                                   :url=>data_url,
                                   :original_filename=>@original_filenames[index],
                                   :content_type=>@content_types[index],
                                   :asset_version=>version)
      end

      #create content_blobs and files, based on previous version chosen content_blobs
      previous_version_asset= asset.find_version(version - 1)
      if previous_version_asset
        previous_version_content_blobs = previous_version_asset.content_blobs
        copying_content_blobs = previous_version_content_blobs.select{|cb| @retained_content_blob_ids.include?(cb.id)}

        copying_content_blobs.each do |cb|
            new_content_blob= asset.content_blobs.create(:url=>cb.url,
                                                         :original_filename=>cb.original_filename,
                                                         :content_type=>cb.content_type,
                                                         :asset_version=>version)
            FileUtils.cp(cb.filepath, new_content_blob.filepath) if File.exists?(cb.filepath)
        end
      end
    end
  end

  def handle_download_zip asset
    #get the list of filename and filepath, {:filename => filepath}
    files_to_download = {}
    if asset.respond_to?(:model_image) && asset.model_image
      model_image = asset.model_image
      filename = check_and_rename_file files_to_download.keys, model_image.original_filename
      files_to_download["#{filename}"] = model_image.file_path
    end
    asset.content_blobs.each do |content_blob|
      if File.exists? content_blob.filepath
        filename = check_and_rename_file files_to_download.keys, content_blob.original_filename
        files_to_download["#{filename}"] = content_blob.filepath
      elsif !content_blob.url.nil?
        downloader=Seek::RemoteDownloader.new
        data_hash = downloader.get_remote_data content_blob.url, nil, nil, nil, true
        filename = check_and_rename_file files_to_download.keys, content_blob.original_filename
        files_to_download["#{filename}"] = data_hash[:data_tmp_path]
      end
    end

    #making zip file
    t = Tempfile.new("#{Time.now.year}#{Time.now.month}#{Time.now.day}_#{asset.class.name.downcase}_#{asset.id}","#{RAILS_ROOT}/tmp")
    # Give the path of the temp file to the zip outputstream, it won't try to open it as an archive.
    Zip::ZipOutputStream.open(t.path) do |zos|
      files_to_download.each do |filename,filepath|
        zos.put_next_entry(filename)
        zos.print IO.read(filepath)
      end
    end

    send_file t.path, :type => 'application/zip', :disposition => 'attachment', :filename => "#{asset.title}.zip"
    # The temp file will be deleted some time...
    t.close
  end

  def check_and_rename_file filename_list, filename
    file = filename.split('.')
    file_format = file.last
    original_name = file.take(file.size - 1).join('.')
    i = 1
    while filename_list.include?(filename)
      filename = original_name + '_' + i.to_s + '.' + file_format
      i += 1
    end
    filename
  end

  def content_type_from_filename filename
    file_format = filename.split('.').last.try(:strip)
    possible_mime_types = mime_types_for_extension file_format
    possible_mime_types.first
  end
end

Seek::AssetsCommon.module_eval do
  include AssetsCommonExtension
end




