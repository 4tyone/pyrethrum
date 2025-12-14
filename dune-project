(lang dune 3.0)
(name pyrethrum)
(version 0.1.0)

(generate_opam_files true)

(source (github anthropics/pyrethrum))
(license MIT)
(authors "Mel Shakobyan")
(maintainers "Mel Shakobyan")

(package
 (name pyrethrum)
 (synopsis "Static analyzer for exhaustive exception handling")
 (description "Pyrethrum analyzes Python code to ensure all declared exceptions are handled exhaustively")
 (depends
  (ocaml (>= 4.14))
  (dune (>= 3.0))
  (yojson (>= 2.0))
  (ppx_deriving (>= 5.0))
  (cmdliner (>= 1.2))
  (fmt (>= 0.9))
  (alcotest (and (>= 1.7) :with-test))))
