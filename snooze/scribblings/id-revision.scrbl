#lang scribble/doc

@(require "base.ss")

@title[#:tag "id+revision"]{IDs and revisions}

Every persistent struct has an @italic{ID} and a @italic{revision}. The ID acts as a primary key in the database, and the revision helps protect against concurrent database updates.

@defproc[(struct-id [struct persistent-struct?]) (U integer? #f)]{
Returns the ID of @scheme[struct], or @scheme[#f] if @scheme[struct] is not saved in the database.

@italic{Warning: Use @scheme[struct-saved?] rather than @scheme[struct-id] to check whether or not a struct has been saved to the database. Changes in later versions of Snooze may affect whether @scheme[struct-id] returns @scheme[#f] for unsaved structs.}}

@defproc[(set-struct-id! [struct persistent-struct?] 
                         [id (U integer? #f)]) void?]{
Sets the @scheme[id] of @scheme[struct]. You should not normally have to use this procedure: Snooze does this automatically when you save or delete a struct.}

@defproc[(struct-revision [struct persistent-struct?]) (U integer? #f)]{
Returns the last revision number of @scheme[struct], or @scheme[#f] if @scheme[struct] is not saved in the database.

The revision number is set to @scheme[0] when a structure is first saved and is incremented on each subsequent save. Snooze raises @scheme[exn:fail:snooze:revision] if a structure has an incompatible revision number when you try to save it. This protects against common concurrency problems.}

@defproc[(set-struct-revision! [struct persistent-struct?] 
                               [rev (U integer? #f)]) void?]{
Sets the revision number of @scheme[struct] to @scheme[rev]. You should not normally have to use this procedure: Snooze does this automatically when you save or delete a struct.}

@defproc[(struct-saved? [struct persistent-struct?]) boolean?]{
Returns @scheme[#t] if @scheme[struct] has been saved to the database and @scheme[#f] if it has not.}