require 'spec_helper'
require Rails.root.join('db', 'post_migrate', '20170628080858_migrate_stage_id_reference_in_background')

RSpec::Matchers.define :have_migrated do |*expected|
  match do |migration|
    BackgroundMigrationWorker.jobs.any? do |job|
      job['enqueued_at'].present? && job['args'] == [migration, expected]
    end
  end

  failure_message do |migration|
    <<-EOS
      Background migration `#{migration}` with args `#{expected.inspect}`
      not migrated!
    EOS
  end
end

RSpec::Matchers.define :have_scheduled_migration do |time, *expected|
  match do |migration|
    BackgroundMigrationWorker.jobs.any? do |job|
      job['args'] == [migration, expected] && job['at'] >= time
    end
  end

  failure_message do |migration|
    <<-EOS
      Background migration `#{migration}` with args `#{expected.inspect}`
      not scheduled!
    EOS
  end
end

describe MigrateStageIdReferenceInBackground, :migration do
  let(:jobs) { table(:ci_builds) }
  let(:stages) { table(:ci_stages) }
  let(:pipelines) { table(:ci_pipelines) }
  let(:projects) { table(:projects) }

  before do
    stub_const('MigrateStageIdReferenceInBackground::BATCH_SIZE', 1)

    projects.create!(id: 123, name: 'gitlab1', path: 'gitlab1')
    pipelines.create!(id: 1, project_id: 123, ref: 'master', sha: 'adf43c3a')

    jobs.create!(id: 1, commit_id: 1, project_id: 123, stage_idx: 2, stage: 'build')
    jobs.create!(id: 2, commit_id: 1, project_id: 123, stage_idx: 2, stage: 'build')
    jobs.create!(id: 3, commit_id: 1, project_id: 123, stage_idx: 1, stage: 'test')
    jobs.create!(id: 4, commit_id: 1, project_id: 123, stage_idx: 3, stage: 'deploy')

    stages.create(id: 101, pipeline_id: 1, project_id: 123, name: 'test')
    stages.create(id: 102, pipeline_id: 1, project_id: 123, name: 'build')
    stages.create(id: 103, pipeline_id: 1, project_id: 123, name: 'deploy')
  end

  it 'correctly schedules background migrations' do
    Sidekiq::Testing.fake! do
      migrate!

      expect(described_class::MIGRATION).to have_migrated(1)
      expect(described_class::MIGRATION).to have_migrated(2)
      expect(described_class::MIGRATION).to have_scheduled_migration(5.minutes, 3)
      expect(described_class::MIGRATION).to have_scheduled_migration(5.minutes, 4)
    end
  end

  it 'schedules background migrations' do
    Sidekiq::Testing.inline! do
      expect(jobs.where(stage_id: nil)).to be_present

      migrate!

      expect(jobs.where(stage_id: nil)).to be_empty
    end
  end
end
