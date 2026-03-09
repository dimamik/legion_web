[
  import_deps: [:phoenix],
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs,heex}"],
  export: [
    locals_without_parens: [legion_dashboard: 1, legion_dashboard: 2]
  ],
  locals_without_parens: [legion_dashboard: 1, legion_dashboard: 2],
  plugins: [Phoenix.LiveView.HTMLFormatter]
]
