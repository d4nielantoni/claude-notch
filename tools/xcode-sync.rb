#!/usr/bin/env ruby
# frozen_string_literal: true
#
# xcode-sync.rb — mantém o projeto do Xcode em dia com os arquivos em disco.
#
# É idempotente de propósito: rodar duas vezes não duplica nada. Faz três coisas:
#
#   1. cria o alvo ClaudeNotchBridge (executável de linha de comando) se faltar;
#   2. registra todo .swift novo no alvo certo, criando os grupos que faltarem;
#   3. embute o binário da ponte em Contents/Helpers do app.
#
# Uso:  ruby tools/xcode-sync.rb [caminho/do/projeto.xcodeproj]

require 'xcodeproj'

PROJECT_PATH  = ARGV[0] || 'boringNotch.xcodeproj'
APP_TARGET    = 'boringNotch'
BRIDGE_TARGET = 'ClaudeNotchBridge'
BRIDGE_PRODUCT = 'claude-notch-bridge'
COPY_PHASE_NAME = 'Embed Claude Notch Bridge'
# Compilado nos DOIS alvos: é o que impede app e ponte de divergirem.
SHARED_SOURCES = ['boringNotch/Claude/ClaudeBridgeContract.swift'].freeze

project = Xcodeproj::Project.open(PROJECT_PATH)
app = project.targets.find { |t| t.name == APP_TARGET }
abort "não achei o alvo #{APP_TARGET}" unless app

changed = []

# --- 1. alvo da ponte ---------------------------------------------------------

bridge = project.targets.find { |t| t.name == BRIDGE_TARGET }
if bridge.nil?
  deployment = app.build_configurations.first.build_settings['MACOSX_DEPLOYMENT_TARGET'] || '14.0'
  swift_version = app.build_configurations.first.build_settings['SWIFT_VERSION'] || '5.0'

  bridge = project.new_target(:command_line_tool, BRIDGE_TARGET, :osx, deployment)
  bridge.build_configurations.each do |config|
    config.build_settings['PRODUCT_NAME'] = BRIDGE_PRODUCT
    config.build_settings['SWIFT_VERSION'] = swift_version
    config.build_settings['MACOSX_DEPLOYMENT_TARGET'] = deployment
    # A ponte roda FORA da caixa de areia: quem a invoca é o Claude Code.
    config.build_settings['ENABLE_APP_SANDBOX'] = 'NO'
    config.build_settings['CODE_SIGN_STYLE'] = 'Automatic'
    config.build_settings['SKIP_INSTALL'] = 'YES'
  end
  changed << "alvo #{BRIDGE_TARGET} criado"
end

# --- 2. arquivos --------------------------------------------------------------

# Devolve (criando se preciso) o grupo que espelha o caminho da pasta.
# Devolve nil para pasta sincronizada: ali o Xcode já inclui tudo sozinho,
# e registrar à mão duplicaria o arquivo na compilação.
def group_for(project, dir)
  group = project.main_group.find_subpath(dir, true)
  return nil if group.is_a?(Xcodeproj::Project::Object::PBXFileSystemSynchronizedRootGroup)

  # Nunca mexer na árvore de origem de um grupo: os arquivos que já estavam lá
  # resolvem o caminho em relação a ela, e trocá-la faz todos parecerem ausentes.
  group
end

def existing_paths(target)
  # Sem filter_map: o Ruby do sistema é 2.6.
  target.source_build_phase.files.map { |bf| bf.file_ref && bf.file_ref.real_path.to_s }.compact
end

def sync(project, target, files, changed)
  known = existing_paths(target)
  files.each do |rel|
    next unless File.exist?(rel)
    abs = File.expand_path(rel)
    next if known.include?(abs)

    group = group_for(project, File.dirname(rel))
    next if group.nil?

    ref = group.files.find { |f| f.real_path.to_s == abs } || group.new_reference(abs)
    target.add_file_references([ref])
    changed << "#{rel} -> #{target.name}"
  end
end

# Só mexemos no que é nosso. O upstream deixa alguns arquivos fora do alvo de
# propósito (Logger.swift, StatusBarMenu.swift e outros); varrer a pasta inteira
# os arrastaria para dentro da compilação, que não é o que este fork veio fazer.
app_sources = Dir.glob('boringNotch/**/Claude*.swift').sort
bridge_sources = Dir.glob('ClaudeNotchBridge/**/*.swift').sort

sync(project, app, app_sources, changed)
sync(project, bridge, bridge_sources, changed)
# O contrato entra nos dois.
sync(project, bridge, SHARED_SOURCES, changed)

# --- 3. embutir a ponte no app ------------------------------------------------

# Só liga app e ponte quando a ponte tem código: um executável sem fontes
# não linka, e derrubaria a compilação do app junto.
if bridge.source_build_phase.files.count.positive?
  unless app.dependencies.any? { |d| d.target == bridge }
    app.add_dependency(bridge)
    changed << 'dependência app -> ponte'
  end

  phase = app.copy_files_build_phases.find { |p| p.name == COPY_PHASE_NAME }
  if phase.nil?
    phase = app.new_copy_files_build_phase(COPY_PHASE_NAME)
    phase.symbol_dst_subfolder_spec = :wrapper
    phase.dst_path = 'Contents/Helpers'
    changed << 'fase de cópia criada'
  end

  product = bridge.product_reference
  unless phase.files.any? { |f| f.file_ref == product }
    build_file = phase.add_file_reference(product)
    build_file.settings = { 'ATTRIBUTES' => ['CodeSignOnCopy'] }
    changed << 'ponte embutida em Contents/Helpers'
  end
end

# --- fim ----------------------------------------------------------------------

if changed.empty?
  puts 'nada a fazer: projeto já está em dia'
else
  project.save
  puts "alteracoes (#{changed.count}):"
  changed.each { |c| puts "  - #{c}" }
end
