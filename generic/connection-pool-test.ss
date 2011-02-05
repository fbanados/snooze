#lang scheme/base

(require "../test-base.ss")

(require scheme/class
         scheme/dict
         scheme/match
         "../snooze.ss")

; Tests ------------------------------------------

;; Uncomment these lines if you want to see what is going on in the connection pool
;(require (planet untyped/unlib/log))
;(start-log-output 'info)

(define (make-connection-pool-tests snooze)
  
  ; -> natural
  (define (acquired-count)
    (get-field acquired-count (send snooze get-database)))
  
  ; -> natural
  (define (available-count)
    (get-field available-count (send snooze get-database)))
  
  ; -> natural
  (define (current-keepalive) 500)
  
  ; (listof numbers) -> (listof numbers)
  (define (simplify numbers)
    (for/fold ([accum null])
              ([num (in-list numbers)])
              (if (or (null? accum) (not (= num (car accum))))
                  (cons num accum)
                  accum)))
  
  ; [natural] -> void
  (define (quick-sleep [millis (quotient (current-keepalive) 2)])
    (sync (alarm-evt (+ (current-inexact-milliseconds) millis)))
    (void))
  
  ; (-> any) -> (listof natural) (listof natural)
  (define (sample-connections thunk)
    (let ([accum1  null]
          [accum2  null]
          [finish? #f])
      (thread (lambda ()
                (let loop ()
                  (unless finish?
                    (set! accum1 (cons (acquired-count)   accum1))
                    (set! accum2 (cons (available-count) accum2))
                    (quick-sleep (quotient (current-keepalive) 10))
                    (loop)))))
      (thunk)
      (quick-sleep)
      (set! finish? #t)
      (values (simplify accum1) 
              (simplify accum2))))
  
  ; (list natural natural natural natural) thunk -> void
  (define-check (check-counts counts thunk)
    (match counts
      [(and counts (list claimed-min
                         claimed-max
                         unclaimed-min
                         unclaimed-max))
       (let-values ([(claimed-profile unclaimed-profile)
                     (sample-connections thunk)])
         (with-check-info (['claimed-profile   claimed-profile]
                           ['unclaimed-profile unclaimed-profile])
           (check-equal? (list (apply min claimed-profile)
                               (apply max claimed-profile)
                               (apply min unclaimed-profile)
                               (apply max unclaimed-profile))
                         counts)))]))
  
  (test-suite "connection-pool.ss"
    
    #:before
    (lambda ()
      (printf "Connection pool tests starting.~n")
      (send snooze disconnect)
      (quick-sleep (current-keepalive)))
    
    #:after
    (lambda ()
      (send snooze connect)
      (printf "Connection pool tests complete.~n"))
    
    (test-case "sanity check"
      ; Mustn't have a connection already claimed when we run these tests:
      (check-counts (list 0 0 5 5) void))
    
    (test-case "one connection"
      (check-counts
       (list 0 1 4 5) 
       (lambda ()
         (send snooze call-with-connection
               (lambda ()
                 (quick-sleep (* (current-keepalive) 2)))
               #f)
         (quick-sleep (* (current-keepalive) 2)))))
    
    (test-case "parallel connections"
      (check-counts
       (list 0 4 1 5) 
       (lambda ()
         (apply
          sync
          (for/list ([i (in-range 4)])
            (thread (lambda ()
                      (send snooze call-with-connection
                            (lambda ()
                              (quick-sleep (* (current-keepalive) 2)))
                            #f)))))
         (quick-sleep (* (current-keepalive) 2)))))
    
    (test-case "sequential connections (connection reuse)"
      (let ([conns null])
        (for/list ([i (in-range 20)])
          (send snooze call-with-connection
                (lambda ()
                  (set! conns (cons (send snooze current-connection) conns)))
                #f))
        (send snooze call-with-connection
              (lambda ()
                (check-not-false (member (send snooze current-connection) conns)))
              #f)))
    
    (test-case "threads killed"
      (for/list ([i (in-range 3)])
        (thread
         (lambda ()
           (send snooze call-with-connection
                 (lambda ()
                   (kill-thread (current-thread)))
                 #f))))
      (quick-sleep)
      (check-counts
       (list 0 0 5 5) 
       (lambda ()
         (quick-sleep (current-keepalive)))))
    
    (test-case "disconnections without connections"
      (for ([i (in-range 1 1000)])
        (send snooze disconnect)))

    (test-case "connections created in response to load"
      (check-counts
       (list 0 10 0 8)
       (lambda ()
         (apply sync
                (for/list ([i (in-range 40)])
                          (thread (lambda ()
                                    (send snooze call-with-connection
                                          (lambda () (sleep 1)) #f))))))))))

; Provides ---------------------------------------

(provide make-connection-pool-tests)