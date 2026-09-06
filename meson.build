project('half-elmish-template', ['c', 'vala'],
          version: '0.1.0',
    meson_version: '>= 0.59.0',
  default_options: [ 'warning_level=2',
                     'werror=false',
                   ],
)


hybrid_mode = get_option('hybrid')
message('Hybrid mode: @0@'.format(hybrid_mode))

i18n = import('i18n')

gnome = import('gnome')

if hybrid_mode == 'b_hybrid'
  add_project_arguments(['--define=B_HYBRID'], language: 'vala')
endif

add_global_arguments([
        '-DGETTEXT_PACKAGE="@0@"'.format(meson.project_name()),
    ],
    language: 'c'
)


subdir('data')
subdir('po')

gnome.post_install(
  gtk_update_icon_cache: true,
  update_desktop_database: true,
)


# Shared library for pure logic (testable without GTK).
# Everything in here must stay GTK-free: no widgets, no Gtk imports.
lib_core_sources = [
  'src/elmish.vala',
  'src/model/messages.vala',
  'src/app-update.vala',
]

lib_core = static_library('half-elmish-core',
  lib_core_sources,
  dependencies: [ dependency('gio-2.0', version: '>= 2.76') ],
)

lib_core_dep = declare_dependency(
  link_with: lib_core,
  include_directories: include_directories('.'),
)


config_data = configuration_data()
config_data.set_quoted('LOCALEDIR', join_paths(get_option('prefix'), get_option('localedir')))
config_data.set_quoted('GETTEXT_PACKAGE', meson.project_name())
config_file = configure_file(
    input: 'src/Config.vala.in',
    output: '@BASENAME@',
    configuration: config_data
)

app_sources = [
  'src/main.vala',
  'src/app-view.vala',
  config_file,
]
if hybrid_mode == 'b_hybrid'
  app_sources += 'src/hybrid_example.vala'
endif

executable(
  meson.project_name(),
  app_sources,
  vala_args: [ '--target-glib=2.76' ],
  dependencies: [
    dependency('gtk4', version: '>= 4.10'),
    lib_core_dep,
  ],
  install: true,
)

subdir('tests')
