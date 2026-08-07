#!/usr/bin/env ruby

require 'xcodeproj'
require 'fileutils'

root = File.expand_path('..', __dir__)
project_path = File.join(root, 'UNASLink.xcodeproj')
FileUtils.rm_rf(project_path)

project = Xcodeproj::Project.new(project_path)
project.root_object.attributes['LastSwiftUpdateCheck'] = '2660'
project.root_object.attributes['LastUpgradeCheck'] = '2660'

app_group = project.main_group.new_group('UNASLinkApp', 'UNASLinkApp')
extension_group = project.main_group.new_group('UNASLinkFinderExtension', 'UNASLinkFinderExtension')
shared_group = project.main_group.new_group('Shared', 'Shared')

app_sources = %w[
  UNASLinkApp.swift
  AppDelegate.swift
  AppState.swift
  ContentView.swift
  LoginWebView.swift
  KeychainStore.swift
  JWTClaims.swift
  UNASAPIClient.swift
].map { |name| app_group.new_file(name) }

extension_sources = %w[FinderSync.swift].map { |name| extension_group.new_file(name) }
shared_sources = %w[Constants.swift].map { |name| shared_group.new_file(name) }

app_group.new_file('Info.plist')
app_group.new_file('UNASLink.entitlements')
asset_catalog = app_group.new_file('Assets.xcassets')
extension_group.new_file('Info.plist')
extension_group.new_file('UNASLinkFinderExtension.entitlements')

app = project.new_target(:application, 'UNASLink', :osx, '14.0')
finder_extension = project.new_target(:app_extension, 'UNASLinkFinderExtension', :osx, '14.0')

app.add_file_references(app_sources + shared_sources)
app.resources_build_phase.add_file_reference(asset_catalog)
finder_extension.add_file_references(extension_sources + shared_sources)
app.add_dependency(finder_extension)

embed_extensions = app.new_copy_files_build_phase('Embed App Extensions')
embed_extensions.dst_subfolder_spec = '13'
embed_extensions.add_file_reference(finder_extension.product_reference)

app.build_configurations.each do |config|
  config.build_settings.merge!({
    'PRODUCT_BUNDLE_IDENTIFIER' => 'com.example.UNASLink',
    'INFOPLIST_FILE' => 'UNASLinkApp/Info.plist',
    'CODE_SIGN_ENTITLEMENTS' => 'UNASLinkApp/UNASLink.entitlements',
    'GENERATE_INFOPLIST_FILE' => 'NO',
    'SWIFT_VERSION' => '5.0',
    'MACOSX_DEPLOYMENT_TARGET' => '14.0',
    'ENABLE_HARDENED_RUNTIME' => 'YES',
    'CODE_SIGN_STYLE' => 'Automatic',
    'ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS' => 'YES',
    'ASSETCATALOG_COMPILER_APPICON_NAME' => 'AppIcon'
  })
end

finder_extension.build_configurations.each do |config|
  config.build_settings.merge!({
    'PRODUCT_BUNDLE_IDENTIFIER' => 'com.example.UNASLink.FinderExtension',
    'INFOPLIST_FILE' => 'UNASLinkFinderExtension/Info.plist',
    'CODE_SIGN_ENTITLEMENTS' => 'UNASLinkFinderExtension/UNASLinkFinderExtension.entitlements',
    'GENERATE_INFOPLIST_FILE' => 'NO',
    'SWIFT_VERSION' => '5.0',
    'MACOSX_DEPLOYMENT_TARGET' => '14.0',
    'ENABLE_HARDENED_RUNTIME' => 'YES',
    'CODE_SIGN_STYLE' => 'Automatic',
    'SKIP_INSTALL' => 'YES'
  })
end

project.build_configurations.each do |config|
  config.build_settings['MACOSX_DEPLOYMENT_TARGET'] = '14.0'
  config.build_settings['SWIFT_VERSION'] = '5.0'
end

project.save

app_scheme = Xcodeproj::XCScheme.new
app_scheme.configure_with_targets(app, nil, launch_target: true)
app_scheme.save_as(project_path, 'UNASLink', true)

puts "Generated #{project_path}"
