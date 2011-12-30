require 'rake/testtask'

Rake::TestTask.new do |task|
  task.name = :default
  task.test_files = FileList['test/test*.rb']
end

task 'db:setup' do
  require 'pg'
  pg = PGconn.open(:dbname => 'postgres')

  pg.exec("DROP DATABASE IF EXISTS secrets_development;")
  pg.exec("CREATE DATABASE secrets_development;")

  pg = PGconn.open(:dbname => 'secrets_development')

  data = pg.exec("select datname from pg_database;")
  data.each do |row|
    p row
  end
  data.clear
end
