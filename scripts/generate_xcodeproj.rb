#!/usr/bin/env ruby
# frozen_string_literal: true

require 'pathname'
require 'xcodeproj'

PROJECT_NAME = 'OpenChat'
PROJECT_PATH = "#{PROJECT_NAME}.xcodeproj"
APP_DIR = Pathname('OpenChat')
TEST_DIR = Pathname('OpenChatTests')
IOS_DEPLOYMENT_TARGET = '17.0'
TOOLS_VERSION = '26.4'
GRDB_REVISION = '36e30a6f1ef10e4194f6af0cff90888526f0c115'
GRDB_URL = 'https://github.com/groue/GRDB.swift.git'
SQLITE_VEC_LOCAL_PATH = 'Packages/SqliteVec'

RESOURCE_EXTENSIONS = %w[
  .xcassets
  .xcstrings
  .png
  .jpg
  .jpeg
  .gif
  .pdf
  .json
  .plist
  .bundle
  .xcprivacy
].freeze

def package_like?(path)
  path.extname == '.xcodeproj'
end

def resource_file?(path)
  RESOURCE_EXTENSIONS.include?(path.extname)
end

def add_directory(group:, directory:, source_target:, test_target: nil, is_test_root: false)
  directory.children.sort_by(&:to_s).each do |entry|
    next if entry.basename.to_s.start_with?('.')

    if entry.directory? && !package_like?(entry)
      child_group = group.new_group(entry.basename.to_s, entry.basename.to_s)
      add_directory(
        group: child_group,
        directory: entry,
        source_target: source_target,
        test_target: test_target,
        is_test_root: is_test_root
      )
      next
    end

    file_ref = group.new_file(entry.basename.to_s)

    if entry.extname == '.swift'
      (is_test_root ? test_target : source_target).source_build_phase.add_file_reference(file_ref, true)
    elsif !is_test_root && resource_file?(entry)
      source_target.resources_build_phase.add_file_reference(file_ref, true)
    end
  end
end

project = Xcodeproj::Project.new(PROJECT_PATH)

app_target = project.new_target(:application, PROJECT_NAME, :ios, IOS_DEPLOYMENT_TARGET)
test_target = project.new_target(:unit_test_bundle, "#{PROJECT_NAME}Tests", :ios, IOS_DEPLOYMENT_TARGET)
test_target.add_dependency(app_target)

project.root_object.attributes['TargetAttributes'] ||= {}
project.root_object.attributes['TargetAttributes'][app_target.uuid] = {
  'CreatedOnToolsVersion' => TOOLS_VERSION,
}
project.root_object.attributes['TargetAttributes'][test_target.uuid] = {
  'CreatedOnToolsVersion' => TOOLS_VERSION,
  'TestTargetID' => app_target.uuid,
}

package_ref = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
package_ref.repositoryURL = GRDB_URL
package_ref.requirement = {
  'kind' => 'revision',
  'revision' => GRDB_REVISION,
}
project.root_object.package_references << package_ref

grdb_dependency = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
grdb_dependency.package = package_ref
grdb_dependency.product_name = 'GRDB'
app_target.package_product_dependencies << grdb_dependency
test_target.package_product_dependencies << grdb_dependency

app_framework_build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
app_framework_build_file.product_ref = grdb_dependency
app_target.frameworks_build_phase.files << app_framework_build_file

test_framework_build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
test_framework_build_file.product_ref = grdb_dependency
test_target.frameworks_build_phase.files << test_framework_build_file

# --- Local SqliteVec Package ---
local_package_ref = project.new(Xcodeproj::Project::Object::XCLocalSwiftPackageReference)
local_package_ref.relative_path = SQLITE_VEC_LOCAL_PATH
project.root_object.package_references << local_package_ref

sqlitevec_dependency = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
sqlitevec_dependency.package = local_package_ref
sqlitevec_dependency.product_name = 'SqliteVec'
app_target.package_product_dependencies << sqlitevec_dependency

sqlitevec_build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
sqlitevec_build_file.product_ref = sqlitevec_dependency
app_target.frameworks_build_phase.files << sqlitevec_build_file

app_group = project.main_group.new_group(PROJECT_NAME, APP_DIR.to_s)
tests_group = project.main_group.new_group("#{PROJECT_NAME}Tests", TEST_DIR.to_s)

add_directory(
  group: app_group,
  directory: APP_DIR,
  source_target: app_target
)

add_directory(
  group: tests_group,
  directory: TEST_DIR,
  source_target: app_target,
  test_target: test_target,
  is_test_root: true
)

[app_target, test_target].each do |target|
  target.build_configurations.each do |config|
    config.build_settings['SWIFT_VERSION'] = '6.0'
    config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = IOS_DEPLOYMENT_TARGET
    config.build_settings['TARGETED_DEVICE_FAMILY'] = '1,2'
    config.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
    config.build_settings['PRODUCT_NAME'] = '$(TARGET_NAME)'
    config.build_settings['SUPPORTS_MACCATALYST'] = 'NO'
  end
end

app_target.build_configurations.each do |config|
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'fukujusou.openchat.com'
  config.build_settings['DEVELOPMENT_TEAM'] = 'GZAC7644XS'
  config.build_settings['CODE_SIGN_STYLE'] = 'Automatic'
  config.build_settings['CURRENT_PROJECT_VERSION'] = '1'
  config.build_settings['MARKETING_VERSION'] = '1.0.0'
  config.build_settings['INFOPLIST_KEY_UIApplicationSceneManifest_Generation'] = 'YES'
  config.build_settings['INFOPLIST_KEY_UILaunchScreen_Generation'] = 'YES'
  config.build_settings['INFOPLIST_KEY_CFBundleDisplayName'] = PROJECT_NAME
  config.build_settings['INFOPLIST_KEY_CFBundleDevelopmentRegion'] = 'en'
  config.build_settings['INFOPLIST_KEY_CFBundleLocalizations'] = 'en zh-Hans'
  config.build_settings['INFOPLIST_KEY_NSPhotoLibraryUsageDescription'] = 'OpenChat uses the photo library to pick character avatars.'
  config.build_settings['INFOPLIST_KEY_NSPhotoLibraryAddUsageDescription'] = 'OpenChat exports generated content and attachments when requested.'
  config.build_settings['INFOPLIST_KEY_NSCameraUsageDescription'] = 'OpenChat uses the camera to capture character avatars.'
end

test_target.build_configurations.each do |config|
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.openchat.app.tests'
  config.build_settings['BUNDLE_LOADER'] = '$(TEST_HOST)'
  config.build_settings['TEST_HOST'] = "$(BUILT_PRODUCTS_DIR)/#{PROJECT_NAME}.app/#{PROJECT_NAME}"
  config.build_settings['LD_RUNPATH_SEARCH_PATHS'] = '$(inherited) @loader_path/Frameworks @loader_path/../../Frameworks'
end

scheme = Xcodeproj::XCScheme.new
scheme.configure_with_targets(app_target, test_target, launch_target: true)
scheme.save_as(PROJECT_PATH, PROJECT_NAME, true)

project.save
