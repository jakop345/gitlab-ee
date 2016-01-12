namespace :gitlab do
  namespace :elastic do
    desc "Indexing repositories"
    task :index_repository do
      Repository.import
    end

    desc "Create indexes in the Elasticsearch from database records"
    task create_index: :environment do
      [Project, Group, User, Issue, MergeRequest, Snippet].each do |klass|
        klass.__elasticsearch__.create_index!
        klass.import
      end
    end
  end
end