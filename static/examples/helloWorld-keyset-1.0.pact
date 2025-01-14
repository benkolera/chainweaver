;;
;; "Hello, world!" smart contract/module
;;

;;---------------------------------
;;
;;  Create an 'admin-keyset' and add some key, for loading this contract!
;;
;;  Make sure the message is signed with this added key as well.
;;
;;  When deploying new contracts, ensure to use a unique keyset
;;  and unique module from any previously deployed contract
;;
;;
;;---------------------------------


;; Keysets cannot be created in code, thus we read them in
;; from the load message data.
(define-keyset 'admin-keyset (read-keyset "admin-keyset"))

;; Define the module.
(module hello-world 'admin-keyset
  "A smart contract to greet the world."
  (defun hello (name:string)
    "Do the hello-world dance"
    (format "Hello {}!" [name]))
)

;; and say hello!
(hello "world")
