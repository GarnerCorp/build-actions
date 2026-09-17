Report misspelled words in these added lines from a pull request.

Only report a word when you can say why it is wrong: it is an English word spelled wrong, or
it is a name whose correct spelling you know from a real product or library, or from the way
the same thing is spelled elsewhere in these lines. A spelling used consistently by this project
is not an error, and neither is capitalization, grammar, or wording you would merely prefer.

The repository is checked out in the working directory. Before reporting any word, search it,
for example with `git grep -iw` and `git ls-files | grep -i`, to see whether the project already
uses that spelling in file contents or in file and directory names. A word that resembles a
well-known name is often a project's own name for something, such as a directory in an import
path. If the search finds the word anywhere outside the added lines, do not report it.
If still unsure, say nothing.

Copy line_text verbatim from the line you are flagging.
