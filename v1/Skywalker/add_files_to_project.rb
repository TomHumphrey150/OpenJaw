#!/usr/bin/env ruby
# Script to add Swift files to Xcode project

require 'xcodeproj'

project_path = File.expand_path('Skywalker.xcodeproj', __dir__)
project = Xcodeproj::Project.open(project_path)
root_path = File.expand_path(__dir__)

# Get the main target
target = project.targets.first

# Get the Skywalker group
skywalker_group = project.main_group['Skywalker']

# Create groups if they don't exist
models_group = skywalker_group['Models'] || skywalker_group.new_group('Models')
services_group = skywalker_group['Services'] || skywalker_group.new_group('Services')
views_group = skywalker_group['Views'] || skywalker_group.new_group('Views')

# Files to add
files_to_add = {
  models_group => [
    File.join(root_path, 'Skywalker/Models/CatchUpDeckBuilder.swift')
  ],
  views_group => [
    File.join(root_path, 'Skywalker/Views/CatchUpModalView.swift')
  ]
}

# Add files to project
files_to_add.each do |group, file_paths|
  file_paths.each do |file_path|
    next unless File.exist?(file_path)

    file_name = File.basename(file_path)

    # Skip if file already exists in group
    next if group.files.any? { |f| f.display_name == file_name }

    # Add file reference
    file_ref = group.new_reference(file_path)

    # Add to build phase
    target.source_build_phase.add_file_reference(file_ref)

    puts "Added: #{file_name}"
  end
end

# Save project
project.save

puts "Project updated successfully!"
