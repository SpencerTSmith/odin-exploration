# Fix Soon:
- GL sync... gotta do something either go full with triple buffering and such or go back to using 'SubData' style funcs
- Better render pass state tracking... maybe push and pop GL state procs? Since we are caching them we'll be able to check those calls and not do em if not necessary

