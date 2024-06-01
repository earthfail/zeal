----------------------------- MODULE EdnParser -----------------------------

(***************************************************************************)
(* To practice writing specifications.  I will follow the specs for        *)
(* transactions commit and what follow                                     *)
(***************************************************************************)

EXTENDS Sequences,Integers

CONSTANTS Tokens,Bad

VARIABLES state,tokensSeq

Last(s)== IF s = <<>>
          THEN -1
          ELSE s[Len(s)]

TypeOK == /\ state \in {"reading","finished","invalid"}
          /\ tokensSeq \in Seq(Tokens \cup {Bad})
          
          
PInit == /\ state = "reading"
         /\ tokensSeq = <<>>

ParseMore == /\ state = "reading"
             /\ Last(tokensSeq) # Bad
             /\ state'\in {"reading","finished","invalid"}
             /\ \E t \in Tokens \cup {Bad}: tokensSeq'=Append(tokensSeq,t)

PInvalid == /\ state \in {"reading","invalid"}
            /\ state'="invalid"
            /\ UNCHANGED tokensSeq

PFinished == /\ state = "finished"
             /\ UNCHANGED <<state,tokensSeq>>

PNext == \/ ParseMore
         \/ PInvalid
         \/ PFinished
             
\*     tokens should be a a finite sequence of predefined sequences
=============================================================================
\* Modification History
\* Last modified Fri May 24 21:16:12 IDT 2024 by surrlim
\* Created Fri May 24 14:06:04 IDT 2024 by surrlim
