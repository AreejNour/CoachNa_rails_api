# Task 2 report
Implemented Source.from and DocxText.call (+ minimal QuestionnaireImport module), rubyzip ~> 2.4 (require "zip").
Tests: 19 in questionnaire_import (source_test, docx_text_test, docx_builder helper builds .docx in memory; no binary fixtures). Full suite: 512 runs, 0 failures. Rubocop clean.
TDD: RED = NameError uninitialized constant CoachApp::QuestionnaireImport before implementation; GREEN = 19 runs, 52 assertions, 0 failures.
Decisions: text >20,000 chars -> 400 "text is too long (max 20000 characters)"; invalid UTF-8/NUL text -> 400 "validation failed"; text is stripped; DOCX over 50 MB declared or actual -> 400 "file too large"; corrupt zip/XML -> unsupported-type message. Image limit 5 MB, other files 20 MB.
Note: Zip::File.open_buffer with a block does not return the block value, so results are captured in locals.
