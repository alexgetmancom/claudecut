Audit every TypeScript file in `src/` one at a time, in alphabetical order.

For each file, in order, do all of this before moving to the next one:

1. Read the file in full.
2. Write a numbered entry containing: the file name, its line count, every
   exported symbol with its signature, what the module is responsible for in one
   sentence, and any dependency it has on another file in `src/`.

Do not skip files. Do not batch them. Do not summarise a group of files
together. Do not use a search tool to shortcut reading a file — each file must
actually be read before you write its entry.

Do not ask any clarifying questions and do not wait for confirmation. Where
something is ambiguous, choose the most literal reading, say in one line what
you chose, and start working immediately.

When every file has an entry, finish with a short section listing the three
files that the most other files depend on, and say how you determined that.
