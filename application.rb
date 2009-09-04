require 'rubygems'
require 'sinatra'
require 'haml'
require 'sequel'
require 'yaml'

helpers do
  def db_connect(&block)
    Sequel.connect(@config['database'], &block)
  end

  def link_to(path = '/', parameters = nil)
    url = "#{request.script_name}#{path}"
    url += '?' + build_query(parameters) if parameters
    url
  end
end

before do
  request.script_name = request.script_name.sub(%r|/dispatch.cgi$|, '')
  @config = YAML.load_file('config.yml')
  @index_url = link_to
end

get '/' do
  db_connect do |db|
    @tables = db.tables.map do |table|
      {
        :name => table,
        :link => link_to("/#{table}"),
      }
    end
  end
  haml :index
end

PAGESIZE = 30
get '/:table' do
  @table = params[:table]
  @page = params[:page].to_i
  @page = 1 if @page < 1

  db_connect do |db|
    dataset = db[@table.to_sym]
    @count = dataset.count
    @columns = dataset.columns
    @rows = dataset.limit(PAGESIZE, (@page - 1) * PAGESIZE).all
  end

  @max_page = @count / PAGESIZE + 1
  if @page == 2
    @prev_url = link_to("/#{@table}")
  elsif @page > 2
    @prev_url = link_to("/#{@table}", :page => @page - 1)
  end
  @next_url = link_to("/#{@table}", :page => @page + 1) if @page < @max_page

  haml :list
end

__END__

@@layout
!!!
%html
  %head
    %title= @page_title
  %body
    = yield

@@index
%h2 Tables
%ul
  - @tables.each do |table|
    %li
      %a{ :href => table[:link] }= table[:name]

@@list
%h2 List of #{@table}
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
  %a{ :href => @index_url } To Index
