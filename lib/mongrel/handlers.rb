
module Mongrel

  # You implement your application handler with this.  It's very light giving
  # just the minimum necessary for you to handle a request and shoot back 
  # a response.  Look at the HttpRequest and HttpResponse objects for how
  # to use them.
  class HttpHandler
    def process(request, response)
    end
  end


  # The server normally returns a 404 response if an unknown URI is requested, but it
  # also returns a lame empty message.  This lets you do a 404 response
  # with a custom message for special URIs.
  class Error404Handler < HttpHandler

    # Sets the message to return.  This is constructed once for the handler
    # so it's pretty efficient.
    def initialize(msg)
      @response = Const::ERROR_404_RESPONSE + msg
    end
    
    # Just kicks back the standard 404 response with your special message.
    def process(request, response)
      response.socket.write(@response)
    end

  end


  # Serves the contents of a directory.  You give it the path to the root
  # where the files are located, and it tries to find the files based on 
  # the PATH_INFO inside the directory.  If the requested path is a
  # directory then it returns a simple directory listing.
  #
  # It does a simple protection against going outside it's root path by
  # converting all paths to an absolute expanded path, and then making sure
  # that the final expanded path includes the root path.  If it doesn't
  # than it simply gives a 404.
  class DirHandler < HttpHandler
    MIME_TYPES = {
      ".css"        =>  "text/css",
      ".gif"        =>  "image/gif",
      ".htm"        =>  "text/html",
      ".html"       =>  "text/html",
      ".jpeg"       =>  "image/jpeg",
      ".jpg"        =>  "image/jpeg",
      ".js"         =>  "text/javascript",
      ".png"        =>  "image/png",
      ".swf"        =>  "application/x-shockwave-flash",
      ".txt"        =>  "text/plain"
    }


    attr_reader :path

    # You give it the path to the directory root and an (optional) 
    def initialize(path, listing_allowed=true, index_html="index.html")
      @path = File.expand_path(path)
      @listing_allowed=listing_allowed
      @index_html = index_html
    end

    # Checks if the given path can be served and returns the full path (or nil if not).
    def can_serve(path_info)
      req = File.expand_path(File.join(@path,path_info), @path)

      if req.index(@path) == 0 and File.exist? req
        # it exists and it's in the right location
        if File.directory? req
          # the request is for a directory
          index = File.join(req, @index_html)
          if File.exist? index
            # serve the index
            return index
          elsif @listing_allowed
            # serve the directory
            req
          else
            # do not serve anything
            return nil
          end
        else
          # it's a file and it's there
          return req
        end
      else
        # does not exist or isn't in the right spot
        return nil
      end
    end


    # Returns a simplistic directory listing if they're enabled, otherwise a 403.
    # Base is the base URI from the REQUEST_URI, dir is the directory to serve 
    # on the file system (comes from can_serve()), and response is the HttpResponse
    # object to send the results on.
    def send_dir_listing(base, dir, response)
      # take off any trailing / so the links come out right
      base.chop! if base[-1] == "/"[-1]

      if @listing_allowed
        response.start(200) do |head,out|
          head['Content-Type'] = "text/html"
          out << "<html><head><title>Directory Listing</title></head><body>"
          Dir.entries(dir).each do |child|
            next if child == "."

            if child == ".."
              out << "<a href=\"#{base}/#{child}\">Up to parent..</a><br/>"
            else
              out << "<a href=\"#{base}/#{child}\">#{child}</a><br/>"
            end
          end
          out << "</body></html>"
        end
      else
        response.start(403) do |head,out|
          out.write("Directory listings not allowed")
        end
      end
    end

    
    # Sends the contents of a file back to the user. Not terribly efficient since it's
    # opening and closing the file for each read.
    def send_file(req, response)
      response.start(200) do |head,out|
        # set the mime type from our map based on the ending
        dot_at = req.rindex(".")
        if dot_at
          ext = req[dot_at .. -1]
          if MIME_TYPES[ext]
            head['Content-Type'] = MIME_TYPES[ext]
          end
        end

        open(req, "rb") do |f|
          out.write(f.read)
        end
      end
    end


    # Process the request to either serve a file or a directory listing
    # if allowed (based on the listing_allowed paramter to the constructor).
    def process(request, response)
      req = can_serve request.params['PATH_INFO']
      if not req
        # not found, return a 404
        response.start(404) do |head,out|
          out << "File not found"
        end
      else
        begin
          if File.directory? req
            send_dir_listing(request.params["REQUEST_URI"],req, response)
          else
            send_file(req, response)
          end
        rescue => details
          response.reset
          response.start(403) do |head,out|
            out << "Error accessing file: #{details}"
            out << details.backtrace.join("\n")
          end
        end
      end
    end

    # There is a small number of default mime types for extensions, but
    # this lets you add any others you'll need when serving content.
    def DirHandler::add_mime_type(extension, type)
      MIME_TYPES[extension] = type
    end

  end
end