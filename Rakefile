require 'rake/testtask'

Rake::TestTask.new do |task|
  task.name = :default
  task.test_files = FileList['test/test*.rb']
end

desc("Reset to empty DynamoDB table")
task('db:reset') do
  require 'fog'
  ddb = Fog::AWS::DynamoDB.new(
    :aws_access_key_id      => ENV['AWS_ACCESS_KEY_ID'],
    :aws_secret_access_key  => ENV['AWS_SECRET_ACCESS_KEY']
  )

  print("Deleting 'good' table.\n")
  begin
    ddb.delete_table('good')
    print("Waiting for 'good' table deletion...\n")
    Fog.wait_for { !ddb.list_tables.body['TableNames'].include?('good') }
  rescue(Excon::Errors::BadRequest)
    # ignore non-existent table error
  end

  print("Creating 'good' table.\n")
  ddb.create_table(
    'good',
    {
      'HashKeyElement'  => { 'AttributeName' => 'user',  'AttributeType' => 'S' },
      'RangeKeyElement' => { 'AttributeName' => 'token', 'AttributeType' => 'S' }
    },
    { 'ReadCapacityUnits' => 10, 'WriteCapacityUnits' => 5 }
  )
  print("Waiting for 'good' table creation...\n")
  Fog.wait_for { ddb.describe_table('good').body['Table']['TableStatus'] == 'ACTIVE' }

  print("db:reset completed.\n")
end
