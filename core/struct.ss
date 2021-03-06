#lang scheme/base

(require "../base.ss")

(require (for-syntax scheme/base
                     (unlib-in syntax))
         scheme/dict
         (unlib-in enumeration symbol)
         "../common/connection.ss"
         "core-snooze-interface.ss")

; Snooze objects ---------------------------------

; (parameter (U snooze<%> #f))
(define current-snooze (make-parameter #f))

; Guids ------------------------------------------

; (struct symbol (U natural symbol))
(define-serializable-struct guid (id) #:transparent #:mutable)

; guid -> boolean
(define (temporary-guid? guid)
  (and (guid? guid)
       (symbol? (guid-id guid))))

; guid -> boolean
(define (database-guid? guid)
  (and (guid? guid)
       (integer? (guid-id guid))))

; property
; guid -> boolean
; guid -> entity
(define-values (prop:guid-entity-box guid-entity? guid-entity-box)
  (make-struct-type-property 'guid-entity-box))

; guid -> entity
(define (guid-entity guid)
  (unbox (guid-entity-box guid)))

; guid -> guid
(define (copy-guid guid)
  ((entity-guid-constructor (guid-entity guid)) (guid-id guid)))

; guid -> void
(define (set-guid-temporary-id! guid)
  (when (database-guid? guid)
    (set-guid-id! guid (gensym/interned (entity-name (guid-entity guid))))))

; Attribute types --------------------------------

; property
; guid-type -> boolean
; guid-type -> entity
(define-values (prop:guid-type-entity-box guid-type-entity? guid-type-entity-box)
  (make-struct-type-property 'guid-type-entity-box))

; (struct boolean)
(define-serializable-struct type (allows-null?) #:transparent)

; guid-type -> entity
(define (guid-type-entity type)
  (unbox (guid-type-entity-box type)))

; (struct boolean)
(define-serializable-struct
  (guid-type type)
  ()
  #:transparent
  #:property
  prop:guid-type-entity-box
  (box #f))

; (struct boolean)
(define-serializable-struct (boolean-type type) () #:transparent)

; (struct boolean number number)
(define-serializable-struct (numeric-type type) (min-value max-value) #:transparent)
(define-serializable-struct (integer-type numeric-type) () #:transparent)
(define-serializable-struct (real-type    numeric-type) () #:transparent)

; (struct boolean (U natural #f))
(define-serializable-struct (character-type type) (max-length) #:transparent)
(define-serializable-struct (string-type character-type) () #:transparent)
(define-serializable-struct (symbol-type character-type) () #:transparent)

; (struct boolean (U natural #f) (U enum #f) (listof symbol))
(define-serializable-struct (enum-type symbol-type) (enum values) #:transparent)

; (struct boolean)
(define-serializable-struct (temporal-type type)          () #:transparent)
(define-serializable-struct (time-utc-type temporal-type) () #:transparent)
(define-serializable-struct (time-tai-type temporal-type) () #:transparent)

; (struct boolean)
(define-serializable-struct (binary-type type) () #:transparent)

; boolean (U enum (listof symbol)) -> enum-type
(define (create-enum-type allow-null? enum+vals)
  (let* ([enum       (if (enum? enum+vals) enum+vals #f)]
         [vals       (if (enum? enum+vals) (enum-values enum+vals) enum+vals)]
         [max-length (foldl max 0 (map string-length (map symbol->string vals)))])
    (make-enum-type allow-null? max-length enum vals)))

; type -> any
(define (type-null type)
  (if (boolean-type? type)
      (void)
      #f))

; type any -> boolean
(define (type-valid? type val [check-constraints? #f])
  (if (equal? val (type-null type))
      (or (not check-constraints?)
          (type-allows-null? type))
      (match type
        [(? guid-type?)                    ((entity-predicate (guid-type-entity type)) val)]
        [(? boolean-type?)                 (boolean? val)]
        [(struct integer-type (_ min max)) (and (integer? val)
                                                (or (not check-constraints?)
                                                    (or (not min) (>= val min))
                                                    (or (not max) (<= val max))))]
        [(struct real-type (_ min max))    (and (number? val)
                                                (or (not check-constraints?)
                                                    (or (not min) (>= val min))
                                                    (or (not max) (<= val max))))]
        [(struct enum-type (_ _ _ vals))   (and (member val vals) #t)]
        [(struct string-type (_ max))      (and (string? val)
                                                (or (not check-constraints?)
                                                    (not max)
                                                    (<= (string-length val) max)))]
        [(struct symbol-type (_ max))      (and (symbol? val)
                                                (or (not check-constraints?)
                                                    (not max)
                                                    (<= (string-length (symbol->string val)) max)))]
        [(? time-tai-type?)                (time-tai? val)]
        [(? time-utc-type?)                (time-utc? val)]
        [(? binary-type?)                  (serializable? val)])))

; type -> symbol
(define (type-name type)
  (cond [(guid-type? type)     (entity-name (guid-type-entity type))]
        [(boolean-type? type)  'boolean]
        [(integer-type? type)  'integer]
        [(real-type? type)     'real]
        [(string-type? type)   'string]
        [(symbol-type? type)   'symbol]
        [(enum-type? type)     'enum]
        [(time-utc-type? type) 'time-utc]
        [(time-tai-type? type) 'time-tai]
        [(binary-type? type)   'binary]))

; type type -> boolean
;
; Returns #t if the arguments are of the same class of type (boolean types, integer types, etc).
(define (type-compatible? type1 type2)
  (or (and (guid-type?     type1) (guid-type?     type2)
           (eq? (guid-type-entity type1)
                (guid-type-entity type2)))
      (and (boolean-type?  type1) (boolean-type?  type2))
      (and (integer-type?  type1) (integer-type?  type2))
      (and (real-type?     type1) (real-type?     type2))
      (and (string-type?   type1) (string-type?   type2))
      (and (symbol-type?   type1) (symbol-type?   type2))
      (and (time-utc-type? type1) (time-utc-type? type2))
      (and (time-tai-type? type1) (time-tai-type? type2))
      (and (binary-type?   type1) (binary-type?   type2))))

; type -> contract
(define (type-contract type)
  (flat-named-contract
   (match type
     [(? guid-type?)                        `(guid-attr/c ,(entity-name (guid-type-entity type)))]
     [(? boolean-type?)                     '(boolean-attr/c)]
     [(struct numeric-type (null? min max)) `(,(if (integer-type? type) 'integer-attr/c 'real-attr/c)
                                              ,@(if min `(#:min-value ,min) null)
                                              ,@(if max `(#:max-value ,max) null))]
     [(struct enum-type (null? _ _ values)) `(enum-attr/c #:values ,values)]
     [(struct character-type (null? max))   `(,(if (symbol-type? type) 'symbol-attr/c 'string-attr/c)
                                              ,@(if max `(#:max-length ,max) null))]
     [(struct time-utc-type (null?))        '(time-utc-attr/c)]
     [(struct time-tai-type (null?))        '(time-tai-attr/c)]
     [(struct binary-type (null?))          '(binary-attr/c)])
   (lambda (val)
     (or (equal? val (type-null type))
         (type-valid? type val)))))

; type
(define type:boolean  (make-boolean-type  #t))
(define type:integer  (make-integer-type  #t #f #f))
(define type:real     (make-real-type     #t #f #f))
(define type:string   (make-string-type   #t #f))
(define type:symbol   (make-symbol-type   #t #f))
(define type:time-tai (make-time-tai-type #t))
(define type:time-utc (make-time-utc-type #t))
(define type:binary   (make-binary-type   #t))

; Models -----------------------------------------

; (struct symbol (hasheqof symbol entity)
(define-struct model (name entities) #:transparent)

; symbol -> model
(define (create-model name)
  (make-model name (make-hasheq)))

; model symbol -> entity
(define (model-entity? model name)
  (and (hash-ref (model-entities model) name #f) #t))

; model symbol -> entity
(define (model-entity model name)
  (hash-ref (model-entities model) name))

; model symbol symbol -> attribute
(define (model-attribute model entity-name attribute-name)
  (entity-attribute (model-entity model entity-name) attribute-name))

; model entity -> void
(define (model-add-entity! model entity)
  (if (hash-ref (model-entities model) (entity-name entity) #f)
      (error "model already contains entity with that name" entity)
      (hash-set! (model-entities model) (entity-name entity) entity)))

; (parameter model)
(define current-model (make-parameter (create-model 'default)))

; Entities ---------------------------------------

; (struct model
;         symbol 
;         symbol
;         symbol
;         string
;         string
;         (snooze-struct any ... -> string)
;         struct-type
;         (any ... -> snooze-struct)
;         ((U snooze-struct any) -> boolean)
;         (snooze-struct natural -> any)
;         (snooze-struct natural any -> void)
;         (any ... -> snooze-struct)
;         ((U snooze-struct any) -> boolean)
;         (#:kw any ... -> snooze-struct)
;         (snooze-struct #:kw any ... -> snooze-struct)
;         ((U natural symbol) -> guid)
;         ((U guid any) -> boolean)
;         (boolean -> guid-type)
;         ((U guid-type any) -> boolean)
;         (listof attribute)
;         (listof (cons attribute (listof attribute)))
;         ((snooze-struct -> snooze-struct) snooze-struct -> snooze-struct)
;         ((snooze-struct -> snooze-struct) snooze-struct -> snooze-struct))
;         (snooze-struct -> (listof check-result))
;         (snooze-struct -> (listof check-result))
(define-struct entity 
  (model
   name
   plural-name
   table-name
   pretty-name
   pretty-name-plural
   pretty-formatter
   struct-type
   private-constructor
   private-predicate
   private-accessor
   private-mutator
   constructor
   predicate
   defaults-constructor
   copy-constructor
   guid-constructor
   guid-predicate
   guid-type-constructor
   guid-type-predicate
   attributes
   default-alias
   default-order
   uniqueness-constraints
   on-save
   on-delete
   save-check
   delete-check)
  #:transparent
  #:mutable
  #:property 
  prop:custom-write
  (lambda (entity out write?)
    ((if write? write display)
     (vector 'entity (entity-name entity))
     out)))

;  model
;  symbol
;  symbol
;  symbol
;  string
;  string
;  (snooze-struct any ... -> string)
;  ((U natural symbol) -> guid)
;  ((U guid any) -> boolean)
;  (boolean -> guid-type)
;  ((U guid-type any) -> boolean)
; ->
;  entity
;
; Entities have mutual dependencies with the struct types they are attached to.
; We can't mutate struct types, so we have to create them first and then patch
; the entity. This procedure gets around the field contracts on entity during
; the creation process.
(define (make-vanilla-entity
         model
         name
         plural-name
         table-name
         pretty-name
         pretty-name-plural
         pretty-formatter
         guid-constructor
         guid-predicate
         guid-type-constructor
         guid-type-predicate)
  (let* ([empty-hook  (lambda (continue conn guid) (continue conn guid))]
         [empty-check (lambda (guid) null)]
         [entity      (make-entity model name plural-name table-name pretty-name pretty-name-plural pretty-formatter
                                   #f                       ; struct type
                                   #f #f #f #f #f #f #f #f  ; constructors and predicates
                                   guid-constructor         ; guid constructor
                                   guid-predicate           ; guid predicate
                                   guid-type-constructor    ; guid type constructor
                                   guid-type-predicate      ; guid type predicate
                                   null                     ; attributes
                                   #f                       ; default-alias
                                   #f                       ; default-order
                                   null                     ; uniqueness-constraints
                                   empty-hook               ; hooks
                                   empty-hook               ;
                                   empty-check              ; validation
                                   empty-check)])           ;
    (model-add-entity! model entity)
    entity))

; entity natural -> guid
(define (entity-make-guid entity id)
  ((entity-guid-constructor entity) id))

; entity -> temporary-guid
(define (entity-make-temporary-guid entity)
  (entity-make-guid entity (gensym/interned (entity-name entity))))

; entity any -> boolean
(define (entity-guid? entity guid)
  ((entity-guid-predicate entity) guid))

; entity [boolean] -> guid-type
(define (entity-make-guid-type entity [allow-null? #f])
  ((entity-guid-type-constructor entity) allow-null?))

; entity any -> boolean
(define (entity-guid-type? entity type)
  ((entity-guid-type-predicate entity) type))

; entity (U symbol attribute) -> boolean
(define (entity-has-attribute? entity name+attr)
  (if (attribute? name+attr)
      (eq? (attribute-entity name+attr) entity)
      (ormap (lambda (attr)
               (eq? (attribute-name attr) name+attr))
             (entity-attributes entity))))

; entity (U symbol attribute) -> boolean
(define (entity-guid-attribute? entity name+attr)
  (or (eq? name+attr (car (entity-attributes entity)))
      (eq? name+attr 'guid)))

; entity (U symbol attribute) -> attribute
(define (entity-attribute entity name+attr)
  (or (if (attribute? name+attr)
          (and (eq? (attribute-entity name+attr) entity)
               name+attr)
          (ormap (lambda (attr)
                   (and (eq? (attribute-name attr) name+attr)
                        attr))
                 (entity-attributes entity)))
      (raise-exn exn:fail:contract
        (format "Attribute not found: ~s ~s" entity name+attr))))

; entity -> (listof attribute)
(define (entity-data-attributes entity)
  (cddr (entity-attributes entity)))

; entity ((connection snooze-struct -> snooze-struct) connection snooze-struct -> snooze-struct) -> void
(define (wrap-entity-on-save! entity hook)
  (let ([default (entity-on-save entity)])
    (set-entity-on-save!
     entity
     (lambda (continue conn struct)
       (hook (cut default continue <> <>) conn struct)))))

; entity ((connection snooze-struct -> snooze-struct) connection snooze-struct -> snooze-struct) -> void
(define (wrap-entity-on-delete! entity hook)
  (let ([default (entity-on-delete entity)])
    (set-entity-on-delete!
     entity
     (lambda (continue conn struct)
       (hook (cut default continue <> <>) conn struct)))))

; Relationships ----------------------------------

; Watch this space...

; Attributes -------------------------------------

; (struct symbol
;         symbol
;         string
;         string
;         type
;         entity
;         integer
;         (snooze<%> -> any)
;         (snooze-struct -> any)
;         (snooze-struct any -> void)
;         (snooze-struct -> any)
;         (snooze-struct any -> void))
(define-struct attribute 
  (name
   column-name
   pretty-name
   pretty-name-plural
   type
   entity
   index
   default-maker
   private-accessor
   private-mutator
   accessor
   mutator)
  #:transparent
  #:property
  prop:custom-write
  (lambda (attribute out write?)
    ((if write? write display)
     (vector 'attr
             (entity-name (attribute-entity attribute))
             (attribute-name attribute))
     out)))

; attribute -> boolean
(define (attribute-primary-key? attr)
  (zero? (attribute-index attr)))

; attribute -> boolean
(define (attribute-foreign-key? attr)
  (and (guid-type? (attribute-type attr))
       (not (zero? (attribute-index attr)))))

; type -> any
(define (attribute-default attr)
  ((attribute-default-maker attr)))

; Snooze structs ---------------------------------

; property
; any -> boolean
; any -> (U entity #f)
(define-values (prop:snooze-struct-entity snooze-struct? snooze-struct-entity)
  (make-struct-type-property 'snooze-struct-entity))

; (parameter (U snooze-struct #f))
(define currently-saving   (make-parameter #f))
(define currently-deleting (make-parameter #f))

; Check results ----------------------------------

; (struct string (hasheqof symbol any))
(define-serializable-struct check-result (message annotations) #:transparent)
(define-serializable-struct (check-success check-result) () #:transparent)    ; okay
(define-serializable-struct (check-problem check-result) () #:transparent)    ; problem
(define-serializable-struct (check-warning check-problem) () #:transparent)   ; problem, can save/delete anyway
(define-serializable-struct (check-error   check-problem) () #:transparent)   ; problem, cannot save/delete
(define-serializable-struct (check-failure check-error) () #:transparent)     ; problem, cannot save/delete, caused by user

; (struct string (hasheqof symbol any) exn)
(define-serializable-struct (check-fatal check-error) (exn) #:transparent)    ; problem, cannot save/delete, caused by exn

; contract
(define annotations/c
  (and/c hash? hash-eq?))

; Provide statements -----------------------------

(provide (all-from-out "core-snooze-interface.ss")
         guid
         struct:guid
         prop:guid-entity-box
         prop:guid-type-entity-box)

(provide/contract
 [current-snooze                       (parameter/c (or/c (is-a?/c snooze<%>) #f))]
 [guid?                                procedure?]
 [temporary-guid?                      (-> any/c boolean?)]
 [database-guid?                       (-> any/c boolean?)]
 [copy-guid                            (-> guid? guid?)]
 [guid-id                              (-> guid? (or/c natural-number/c symbol?))]
 [set-guid-id!                         (-> guid? (or/c natural-number/c symbol?) void?)]
 [set-guid-temporary-id!               (-> guid? void?)]
 [guid-entity-box                      (-> struct-type? box?)]
 [guid-entity                          (-> guid? entity?)]
 [guid-type-entity-box                 (-> struct-type? box?)]
 [guid-type-entity                     (-> guid-type? entity?)]
 [struct type                          ([allows-null? boolean?])]
 [struct (guid-type type)              ([allows-null? boolean?])]
 [struct (boolean-type type)           ([allows-null? boolean?])]
 [struct (numeric-type type)           ([allows-null? boolean?]
                                        [min-value    (or/c number? #f)]
                                        [max-value    (or/c number? #f)])]
 [struct (integer-type numeric-type)   ([allows-null? boolean?]
                                        [min-value    (or/c integer? #f)]
                                        [max-value    (or/c integer? #f)])]
 [struct (real-type numeric-type)      ([allows-null? boolean?]
                                        [min-value    (or/c number? #f)]
                                        [max-value    (or/c number? #f)])]
 [struct (character-type type)         ([allows-null? boolean?]
                                        [max-length   (or/c natural-number/c #f)])]
 [struct (string-type character-type)  ([allows-null? boolean?]
                                        [max-length   (or/c natural-number/c #f)])]
 [struct (symbol-type character-type)  ([allows-null? boolean?]
                                        [max-length   (or/c natural-number/c #f)])]
 [struct (enum-type symbol-type)       ([allows-null? boolean?]
                                        [max-length   (or/c natural-number/c #f)]
                                        [enum         (or/c enum? #f)]
                                        [values       (listof symbol?)])]
 [struct (temporal-type type)          ([allows-null? boolean?])]
 [struct (time-utc-type temporal-type) ([allows-null? boolean?])]
 [struct (time-tai-type temporal-type) ([allows-null? boolean?])]
 [struct (binary-type type)            ([allows-null? boolean?])]
 [create-enum-type                     (-> boolean? (or/c enum? (listof symbol?)) enum-type?)]
 [type-null                            (-> type? any)]
 [type-valid?                          (-> type? any/c boolean?)]
 [type-name                            (-> type? symbol?)]
 [type-compatible?                     (-> type? type? boolean?)]
 [type-contract                        (-> type? contract?)]
 [type:boolean                         boolean-type?]
 [type:integer                         integer-type?]
 [type:real                            real-type?]
 [type:string                          string-type?]
 [type:symbol                          symbol-type?]
 [type:time-tai                        time-tai-type?]
 [type:time-utc                        time-utc-type?]
 [type:binary                          binary-type?]
 [struct model                         ([name                   symbol?]
                                        [entities               (hash/c symbol? entity?)])]
 [create-model                         (-> symbol? model?)]
 [model-entity?                        (-> model? symbol? boolean?)]
 [model-entity                         (-> model? symbol? entity?)]
 [model-attribute                      (-> model? symbol? symbol? entity?)]
 [model-add-entity!                    (-> model? entity? void?)]
 [current-model                        (parameter/c model?)]
 [struct entity                        ([model                  model?]
                                        [name                   symbol?]
                                        [plural-name            symbol?]
                                        [table-name             symbol?]
                                        [pretty-name            string?]
                                        [pretty-name-plural     string?]
                                        [pretty-formatter       procedure?]
                                        [struct-type            struct-type?]
                                        [private-constructor    procedure?]
                                        [private-predicate      procedure?]
                                        [private-accessor       procedure?]
                                        [private-mutator        procedure?]
                                        [constructor            procedure?]
                                        [predicate              procedure?]
                                        [defaults-constructor   procedure?]
                                        [copy-constructor       procedure?]
                                        [guid-constructor       (-> (or/c natural-number/c symbol?) guid?)]
                                        [guid-predicate         (-> any/c boolean?)]
                                        [guid-type-constructor  (-> boolean? guid-type?)]
                                        [guid-type-predicate    (-> any/c boolean?)]
                                        [attributes             (listof attribute?)]
                                        [default-alias          any/c]
                                        [default-order          list?]
                                        [uniqueness-constraints (listof (cons/c attribute? (listof attribute?)))]
                                        [on-save                (-> (-> connection? snooze-struct? snooze-struct?)
                                                                    connection?
                                                                    snooze-struct?
                                                                    snooze-struct?)]
                                        [on-delete              (-> (-> connection? snooze-struct? snooze-struct?)
                                                                    connection?
                                                                    snooze-struct?
                                                                    snooze-struct?)]
                                        [save-check             procedure?]
                                        [delete-check           procedure?])]
 [make-vanilla-entity                  (-> model?
                                           symbol?
                                           symbol?
                                           symbol?
                                           string?
                                           string?
                                           procedure?
                                           procedure?
                                           procedure?
                                           procedure?
                                           procedure?
                                           entity?)]
 [entity-make-guid                     (-> entity? (or/c natural-number/c symbol?) guid?)]
 [entity-make-temporary-guid           (-> entity? temporary-guid?)]
 [entity-guid?                         (-> entity? any/c boolean?)]
 [entity-make-guid-type                (->* (entity?) (boolean?) guid-type?)]
 [entity-guid-type?                    (-> entity? any/c boolean?)]
 [entity-has-attribute?                (-> entity? (or/c symbol? attribute?) boolean?)]
 [entity-guid-attribute?               (-> entity? (or/c symbol? attribute?) boolean?)]
 [entity-attribute                     (-> entity? (or/c symbol? attribute?) attribute?)]
 [entity-data-attributes               (-> entity? (listof attribute?))]
 [wrap-entity-on-save!                 (-> entity?
                                           (-> (-> connection? snooze-struct? snooze-struct?)
                                               connection?
                                               snooze-struct?
                                               snooze-struct?)
                                           void?)]
 [wrap-entity-on-delete!               (-> entity?
                                           (-> (-> connection? snooze-struct? snooze-struct?)
                                               connection?
                                               snooze-struct?
                                               snooze-struct?)
                                           void?)]
 [struct attribute                     ([name                 symbol?]
                                        [column-name          symbol?]
                                        [pretty-name          string?]
                                        [pretty-name-plural   string?]
                                        [type                 type?]
                                        [entity               entity?]
                                        [index                integer?]
                                        [default-maker        procedure?]
                                        [private-accessor     procedure?]
                                        [private-mutator      procedure?]
                                        [accessor             procedure?]
                                        [mutator              procedure?])]
 [attribute-primary-key?               (-> attribute? boolean?)]
 [attribute-foreign-key?               (-> attribute? boolean?)]
 [attribute-default                    (-> attribute? any)]
 [prop:snooze-struct-entity            struct-type-property?]
 [snooze-struct?                       (-> any/c boolean?)]
 [snooze-struct-entity                 (-> snooze-struct? entity?)]
 [currently-saving                     (parameter/c (or/c snooze-struct? #f))]
 [currently-deleting                   (parameter/c (or/c snooze-struct? #f))]
 [struct check-result                  ([message string?] [annotations annotations/c])]
 [struct (check-success check-result)  ([message string?] [annotations annotations/c])]
 [struct (check-problem check-result)  ([message string?] [annotations annotations/c])]
 [struct (check-warning check-problem) ([message string?] [annotations annotations/c])]
 [struct (check-error   check-problem) ([message string?] [annotations annotations/c])]
 [struct (check-failure check-error)   ([message string?] [annotations annotations/c])]
 [struct (check-fatal   check-error)   ([message string?] [annotations annotations/c] [exn exn?])])
