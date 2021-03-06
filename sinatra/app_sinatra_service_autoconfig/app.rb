require 'sinatra'
require 'redis'
require 'json'
require 'mongo'
require 'mysql2'
require 'carrot'
require 'uri'
require 'pg'
require 'aws/s3'
require 'cfautoconfig'

$stdout.sync = true

get '/env' do
  ENV['VCAP_SERVICES']
end

get '/' do
  'hello from sinatra'
end

get '/crash' do
  Process.kill("KILL", Process.pid)
end

get '/service/redis/:key' do
  redis = load_redis
  redis[params[:key]]
end

post '/service/redis/:key' do
  redis = load_redis
  redis[params[:key]] = request.env["rack.input"].read
end

post '/service/mongo/:key' do
  coll = load_mongo
  value = request.env["rack.input"].read
  coll.insert( { '_id' => params[:key], 'data_value' => value } )
  value
end

get '/service/mongo/:key' do
  coll = load_mongo
  coll.find('_id' => params[:key]).to_a.first['data_value']
end

not_found do
  'This is nowhere to be found.'
end

post '/service/mysql/:key' do
  client = load_mysql
  value = request.env["rack.input"].read
  result = client.query("insert into data_values (id, data_value) values('#{params[:key]}','#{value}');")
  client.close
  value
end

get '/service/mysql/:key' do
  client = load_mysql
  result = client.query("select data_value from  data_values where id = '#{params[:key]}'")
  value = result.first['data_value']
  client.close
  value
end

post '/service/postgresql/:key' do
  client = load_postgresql
  value = request.env["rack.input"].read
  result = client.query("select * from data_values where id = '#{params[:key]}'")
  if result.count > 0
    client.query("update data_values set data_value='#{value}' where id = '#{params[:key]}'")
  else
    client.query("insert into data_values (id, data_value) values('#{params[:key]}','#{value}');")
  end
  client.close
  value
end

get '/service/postgresql/:key' do
  client = load_postgresql
  value = client.query("select data_value from  data_values where id = '#{params[:key]}'").first['data_value']
  client.close
  value
end

post '/service/rabbit/:key' do
  value = request.env["rack.input"].read
  client = rabbit_service
  write_to_rabbit(params[:key], value, client)
  value
end

get '/service/rabbit/:key' do
  client = rabbit_service
  read_from_rabbit(params[:key], client)
end

post '/service/rabbitmq/:key' do
  value = request.env["rack.input"].read
  client = rabbit_service
  write_to_rabbit(params[:key], value, client)
  value
end

get '/service/rabbitmq/:key' do
  client = rabbit_service
  read_from_rabbit(params[:key], client)
end

post '/service/blob/:object' do
  load_blob
  begin
    AWS::S3::Bucket.create("datavalues")
  rescue
  end
  AWS::S3::S3Object.store(params[:object], request.body, "datavalues")
end

get '/service/blob/:object' do
  load_blob
  AWS::S3::S3Object.value(params[:object], "datavalues")
end

def load_redis
  Redis.new({:host => '127.0.0.1', :port => 6379, :password => 'testpw'})
end

def load_mysql
  client = Mysql2::Client.new(:host => '127.0.0.1', :username =>'testuser', :port => 3306, :password => 'testpw', :database => 'testdb')
  client.query("Create table IF NOT EXISTS data_values ( id varchar(20), data_value varchar(20)); ")
  client
end

def load_mongo
  conn = Mongo::Connection.new('127.0.0.1', 4567)
  db = conn['testdb']
  coll = db['data_values'] #if db.authenticate(mongodb_service['username'], mongodb_service['password'])
end

def load_postgresql
  client = PGconn.open('127.0.0.1', '8675', :dbname => 'testdb', :user => 'testuser', :password => 'testpw')
  client.query("create table data_values (id varchar(20), data_value varchar(20));") if client.query("select * from information_schema.tables where table_name = 'data_values';").first.nil?
  client
end

def load_blob
  AWS::S3::Base.establish_connection!(
    :access_key_id      => "myid",
    :secret_access_key  => "mypwd"
  )
end

def rabbit_service
  Carrot.new( :host => '127.0.0.1', :port => 12345, :user => 'testuser', :pass => 'testpass', :vhost => 'vhost' )
end

def write_to_rabbit(key, value, client)
  q = client.queue(key)
  q.publish(value)
end

def read_from_rabbit(key, client)
  q = client.queue(key)
  msg = q.pop(:ack => true)
  q.ack
  msg
end
