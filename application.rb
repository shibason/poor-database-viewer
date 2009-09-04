require 'rubygems'
require 'sinatra'
require 'haml'
require 'sass'
require 'sequel'
require 'yaml'

configure do
  set :config, YAML.load_file('config.yml')
  set :pagesize, 30
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
end

before do
  request.script_name = request.script_name.sub(%r|/dispatch.cgi$|, '')
  headers('Cache-Control' => 'no-cache',
          'Pragma' => 'no-cache',
          'Expires' => '0')
  @index_url = link_to
  @css_url = link_to('/resource/css')
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
  @table = table
  @page = page.to_i
  @page = 1 if @page < 1

  db_connect do |db|
    dataset = db[@table.to_sym]
    @count = dataset.count
    @columns = dataset.columns
    @rows = dataset.limit(options.pagesize, (@page - 1) * options.pagesize).all
  end

  @max_page = @count / options.pagesize + 1
  if @page == 2
    @prev_url = link_to("/list/#{@table}")
  elsif @page > 2
    @prev_url = link_to("/list/#{@table}/#{@page - 1}")
  end
  @next_url = link_to("/list/#{@table}/#{@page + 1}") if @page < @max_page

  @page_title = "List of #{@table}"
  haml :list
end

get '/resource/css' do
  content_type 'text/css', :charset => 'utf-8'
  sass :css
end

__END__

@@layout
!!!
%html
  %head
    %meta{ 'http-equiv' => 'Content-Type', |
           :content => 'text/html; charset=UTF-8' }
    %title= @page_title
    %link{ :rel => 'stylesheet', :type => 'text/css', :href => @css_url }
  %body
    = yield

@@index
%h2= @page_title
%ul
  - @tables.each do |table|
    %li
      %a{ :href => table[:link] }= table[:name]

@@list
%h2= @page_title
%table
  %tr
    - @columns.each do |column|
      %th= column
  - @rows.each do |row|
    %tr
      - row.each do |name, value|
        %td= value
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

@@css
body
  :margin 20px
table
  :border-collapse collapse
th
  :background-color #f5f5f5
th, td
  :padding 0.2em
  :border 1px solid #808080
