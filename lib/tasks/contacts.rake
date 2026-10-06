namespace :contacts do
  desc "Move names out of custom fields and clear \"NA\" names (see NameCleanup); APPLY=1 to change anything"
  task clean_up_names: :environment do
    apply = ENV["APPLY"] == "1"

    KeilaProject.order(:name).each do |project|
      result = NameCleanup.run(project, apply:)
      puts "Project #{project.name}:"
      NameCleanup::NAME_FIELDS.each do |field|
        puts "  #{field}: custom fields #{result.custom_keys[field].map(&:inspect).join(', ').presence || '(none)'}; " \
             "#{result.filled[field]} filled from them, #{result.cleared[field]} \"NA\" cleared"
      end
      puts "  #{result.contacts_changed} contact(s) #{apply ? 'changed' : 'to change'}"
      puts "  Custom fields #{apply ? 'removed' : 'to remove'}: #{result.removed_keys.map(&:inspect).join(', ').presence || '(none)'}"
      if result.conflicts.any?
        puts "  #{result.conflicts.size} conflict(s), left alone:"
        result.conflicts.each do |conflict|
          custom = conflict.custom.map { |key, value| "#{key.inspect}: #{value.inspect}" }.join(", ")
          puts "    #{conflict.contact.email} #{conflict.field}: #{conflict.built_in.inspect} vs. #{custom}"
        end
      end
    end

    puts apply ? "Done. Review the sync before pushing to Keila." : "Dry run, nothing changed. APPLY=1 to apply."
  end
end
