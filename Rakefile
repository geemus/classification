require 'rubygems'
require 'bundler/setup'

require 'rake/testtask'

require './lib/classification'

require 'queue_classic'


Rake::TestTask.new do |task|
  task.name = :default
  task.test_files = FileList['test/test*.rb']
end

desc('destroy databases for specified environment')
task('db:nuke', [:environment]) do |task, args|
  args.with_defaults(:environment => 'development')
  ddb = Classification::DDB.new.connection
  tables_to_delete = ddb.list_tables.body['TableNames'].select {|table| table =~ /classification\.#{args.environment}\..*/}
  printf("Tables to delete #{tables_to_delete.inspect}... ")
  tables_to_delete.each do |table|
    ddb.delete_table(table)
  end
  Fog.wait_for { !ddb.list_tables.body['TableNames'].any? {|table| tables_to_delete.include?(table)} }
  printf("done\n")
end

namespace :qc do
  desc "Start a new worker for the (default or $QUEUE) queue"
  task :work do
    QC::Worker.new.start
  end

  desc "Returns the number of jobs in the (default or QUEUE) queue"
  task :count do
    puts QC::Worker.new.queue.count
  end

  desc "Setup queue_classic tables and funtions in database"
  task :create do
    QC::Setup.create
  end

  desc "Remove queue_classic tables and functions from database."
  task :drop do
    QC::Setup.drop
  end
end
