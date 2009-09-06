require 'rubygems'
require 'sinatra'
require 'haml'
require 'sequel'
require 'yaml'

configure do
  config = YAML.load_file('config.yml')
  set :db_config, config['database']
  set :pagesize, config['pagesize'] || 30
  set :truncate_size, 32
  if haml = config['haml']
    set :haml, { :format => haml['format'].to_sym } if haml['format']
  end
end

helpers do
  def db_connect
    Sequel.connect(options.db_config) do |db|
      if set_names = options.db_config['set_names']
        db << "SET NAMES #{db.literal(set_names)}"
      end
      yield db
    end
  end

  def link_to(table = nil, primary_value = nil, parameters = nil)
    url = request.script_name + '/'
    if table
      url += escape(table)
      url += '/' + escape(primary_value) if primary_value
    end
    url += '?' + build_query(parameters) if parameters
    url
  end

  def get_primary_key(schema)
    schema.find { |key, options| options[:primary_key] }[0]
  end

  def truncate(value)
    if value.is_a?(String) && value.size > options.truncate_size
      value = value[0, options.truncate_size] + '...'
    end
    value
  end
end

before do
  request.script_name = request.script_name.sub(%r|/dispatch.cgi$|, '')
  @index_url = link_to
end

get '/' do
  @page_title = 'List of Tables'
  db_connect do |db|
    @tables = db.tables.map do |table|
      { :name => table, :link => link_to(table) }
    end
  end
  haml :index
end

get '/:table' do |table|
  @page_title = "Records of '#{table}'"
  @table = table
  @page = params[:page].to_i
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
    @prev_url = link_to(table)
  elsif @page > 2
    @prev_url = link_to(table, nil, :page => @page - 1)
    @head_url = link_to(table)
  end
  @next_url = link_to(table, nil, :page => @page + 1) if @page < @max_page
  if @page + 1 < @max_page
    @last_url = link_to(table, nil, :page => @max_page)
  end

  haml :list
end

get '/:table/:primary_value' do |table, primary_value|
  is_new = params[:new]
  if is_new
    @page_title = "Create new record of '#{table}'"
    @edit_url = link_to(table)
    @edit_method = 'put'
  else
    @primary_value = primary_value
    @page_title = "Update record of '#{table}'"
    @edit_url = link_to(table, primary_value)
    @edit_method = 'post'
    @delete_url = link_to(table, primary_value)
  end

  @columns = []
  db_connect do |db|
    schema = db.schema(table)
    @primary_key = get_primary_key(schema)
    if is_new
      values = {}
    else
      values = db[table.to_sym][@primary_key => primary_value]
    end
    schema.each do |key, options|
      next if key == @primary_key
      type = options[:type]
      type = :text if type == :string && !options[:db_type].include?('(')
      @columns << {
        :key => key,
        :value => values[key],
        :type => type
      }
    end
  end

  haml :view
end

def build_columns(params, schema, primary_key)
  columns = {}
  schema.each do |key, options|
    next if key == primary_key
    next unless params.has_key?(key.to_s)
    columns[key] = params[key.to_s]
  end
  columns
end

put '/:table' do |table|
  db_connect do |db|
    schema = db.schema(table)
    primary_key = get_primary_key(schema)
    columns = build_columns(params, schema, primary_key)
    db[table.to_sym].insert(columns)
  end
  redirect link_to(table)
end

post '/:table/:primary_value' do |table, primary_value|
  db_connect do |db|
    schema = db.schema(table)
    primary_key = get_primary_key(schema)
    columns = build_columns(params, schema, primary_key)
    db[table.to_sym].filter(primary_key => primary_value).update(columns)
  end
  redirect link_to(table)
end

delete '/:table/:primary_value' do |table, primary_value|
  db_connect do |db|
    primary_key = get_primary_key(db.schema(table))
    db[table.to_sym].filter(primary_key => primary_value).delete
  end
  redirect link_to(table)
end

__END__
@@layout
!!!
%html
  %head
    %meta{ 'http-equiv' => 'Content-Type', |
           :content => 'text/html; charset=UTF-8' }
    %meta{ 'http-equiv' => 'Cache-Control', :content => 'no-cache' }
    %meta{ 'http-equiv' => 'Pragma', :content => 'no-cache' }
    %meta{ 'http-equiv' => 'Expires', :content => '0' }
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
        %a{ :href => link_to(@table, primary_value) }&= primary_value
      - row.each do |key, value|
        %td&= truncate(value)
%p
  total #{@count} records
  %a{ :href => link_to(@table, '_', :new => 1) } => Create new record
- if @max_page > 1
  %p
    - if @head_url
      %a{ :href => @head_url } Head
    - if @prev_url
      %a{ :href => @prev_url } Prev
    %span #{@page} / #{@max_page}
    - if @next_url
      %a{ :href => @next_url } Next
    - if @last_url
      %a{ :href => @last_url } Last
%p
  %a{ :href => @index_url } Index

@@view
%form{ :method => 'post', :action => @edit_url }
  %input{ :type => 'hidden', :name => '_method', :value => @edit_method }
  %table
    - if @primary_value
      %tr
        %th= @primary_key
        %td&= @primary_value
    - @columns.each do |column|
      %tr
        %th= column[:key]
        %td
          - case column[:type]
          - when :string
            %input{ :type => 'text', :name => column[:key], |
                    :size => 60, :value => escape_html(column[:value]) }
          - when :text
            %textarea{ :name => column[:key], |
                       :rows => 3, :cols => 60 }&= column[:value]
          - else
            %input{ :type => 'text', :name => column[:key], |
                    :size => 40, :value => escape_html(column[:value]) }
  %p
    %input{ :type => 'submit', :value => 'Send' }
- if @delete_url
  %p
    %form{ :method => 'post', :action => @delete_url, |
           :onsubmit => 'return confirm("realy?")' }
      %input{ :type => 'hidden', :name => '_method', :value => 'delete' }
      %input{ :type => 'submit', :value => 'Delete' }
%p
  %a{ :href => back } Back
  %a{ :href => @index_url } Index
