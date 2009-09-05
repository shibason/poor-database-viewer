require 'rubygems'
require 'sinatra'
require 'haml'
require 'sequel'
require 'yaml'

if Rack.version <= '1.0'
  module Rack
    class Request
      def POST
        if @env["rack.request.form_input"].eql? @env["rack.input"]
          @env["rack.request.form_hash"]
        elsif form_data? || parseable_data?
          @env["rack.request.form_input"] = @env["rack.input"]
          unless @env["rack.request.form_hash"] =
              Utils::Multipart.parse_multipart(env)
            form_vars = @env["rack.input"].read

            # Fix for Safari Ajax postings that always append \0
            form_vars.sub!(/\0\z/, '')

            @env["rack.request.form_vars"] = form_vars
            @env["rack.request.form_hash"] = Utils.parse_nested_query(form_vars)

            begin
              @env["rack.input"].rewind
            rescue Errno::ESPIPE
            end
          end
          @env["rack.request.form_hash"]
        else
          {}
        end
      end
    end
  end
end

configure do
  config = YAML.load_file('config.yml')
  set :config, config
  set :pagesize, config['pagesize'] || 30
  if haml = config['haml']
    set :haml, { :format => haml['format'].to_sym } if haml['format']
  end
end

helpers do
  def db_connect(&block)
    Sequel.connect(options.config['database'], &block)
  end

  def link_to(path = '/', parameters = nil)
    url = "#{request.script_name}#{path}"
    url += '?' + build_query(parameters) if parameters
    url
  end

  def get_primary_key(schema)
    schema.find { |key, options| options[:primary_key] }[0]
  end

  def get_column_type(schema, target_key)
    options = schema.find { |key, options| key == target_key }[1]
    type = options[:type]
    return :text if type == :string && !options[:db_type].include?('(')
    type
  end
end

before do
  request.script_name = request.script_name.sub(%r|/dispatch.cgi$|, '')
  headers('Cache-Control' => 'no-cache',
          'Pragma' => 'no-cache',
          'Expires' => '0')
  @index_url = link_to
end

get '/' do
  db_connect do |db|
    @tables = db.tables.map do |table|
      { :name => table, :link => link_to("/list/#{table}") }
    end
  end
  @page_title = 'List of tables'
  haml :index
end

get %r|/list/([^/?&#]+)(?:/([^/?&#]+))?| do |table, page|
  @page = page.to_i
  @page = 1 if @page < 1

  db_connect do |db|
    schema = db.schema(table)
    @columns = schema.map { |key, optoins| key }
    @primary_key = get_primary_key(schema)
    dataset = db[table.to_sym]
    @count = dataset.count
    @rows = dataset.limit(options.pagesize, (@page - 1) * options.pagesize).all
  end

  @max_page = @count / options.pagesize + 1
  if @page == 2
    @prev_url = link_to("/list/#{table}")
  elsif @page > 2
    @prev_url = link_to("/list/#{table}/#{@page - 1}")
  end
  @next_url = link_to("/list/#{table}/#{@page + 1}") if @page < @max_page

  @page_title = "List of #{table}"
  @view_url = link_to("/view/#{table}/")
  haml :list
end

get '/view/:table/:primary_value' do |table, primary_value|
  @columns = []
  db_connect do |db|
    schema = db.schema(table)
    primary_key = get_primary_key(schema)
    db[table.to_sym][ primary_key => primary_value ].each do |key, value|
      next if key == primary_key
      @columns << {
        :key => key,
        :value => escape_html(value),
        :type => get_column_type(schema, key)
      }
    end
  end
  @page_title = "Edit '#{primary_value}' record of #{table}"
  @edit_url = link_to("/update/#{table}/#{escape(primary_value)}")
  @delete_url = link_to("/delete/#{table}/#{escape(primary_value)}")
  haml :view
end

post '/update/:table/:primary_value' do |table, primary_value|
  # not yet implemented
  redirect link_to("/list/#{table}")
end

delete '/delete/:table/:primary_value' do |table, primary_value|
  # not yet implemented
  redirect link_to("/list/#{table}")
end

__END__

@@layout
!!!
%html
  %head
    %meta{ 'http-equiv' => 'Content-Type', |
           :content => 'text/html; charset=UTF-8' }
    %title&= @page_title
    %style{ :type => 'text/css' }
      :sass
        body
          :margin 20px
        table
          :border-collapse collapse
        th
          :background-color #f5f5f5
        th, td
          :padding 0.2em
          :border 1px solid #808080
  %body
    %h2&= @page_title
    = yield

@@index
%ul
  - @tables.each do |table|
    %li
      %a{ :href => table[:link] }= table[:name]

@@list
%table
  %tr
    - @columns.each do |column|
      %th= column
  - @rows.each do |row|
    %tr
      %td
        - primary_value = row.delete(@primary_key)
        %a{ :href => @view_url + escape(primary_value) }&= primary_value
      - row.each do |key, value|
        %td&= value
%p total #{@count} records
%p
  - if @max_page > 1
    - if @prev_url
      %a{ :href => @prev_url } Prev
    %span #{@page} / #{@max_page}
    - if @next_url
      %a{ :href => @next_url } Next
%p
  %a{ :href => @index_url } Index

@@view
%form{ :method => 'post', :action => @edit_url }
  %table
    - @columns.each do |column|
      %tr
        %th= column[:key]
        %td
          - case column[:type]
          - when :string
            %input{ :type => 'text', :name => column[:key], |
                    :size => 40, :value => column[:value] }
          - when :text
            %textarea{ :name => column[:key], |
                       :rows => 3, :cols => 40 }= column[:value]
          - else
            %input{ :type => 'text', :name => column[:key], |
                    :size => 20, :value => column[:value] }
  %p
    %input{ :type => 'submit', :value => 'Send' }
%p
  %form{ :method => 'post', :action => @delete_url, |
         :onsubmit => 'return confirm("realy?")' }
    %input{ :type => 'hidden', :name => '_method', :value => 'delete' }
    %input{ :type => 'submit', :value => 'Delete' }
%p
  %a{ :href => back } Back
  %a{ :href => @index_url } Index
