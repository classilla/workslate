# Rock, Paper, Scissors
# best out of three
# public domain, because who would take credit for *this*?

.fwidth 13
.dwidth 9
.worksheet "--RPS!--"
.startcell E1

A1.3-" "
# don't do B1 or C1 because we have formulae there
B5.3-" "
C5.3-" "

#      12345678901234
D1.14-"4-digit seed: "
E1.14-6502

D2.14=If(IsNA(I4),"Column A: you ","")
E2.14=If(IsNA(I4),"Column B: CPU ","")

# no string comparisons in Workslate, so must play by number
#   12345678901234
D3=If(IsNA(I4),"0=PAPER",If(I4>0,"YOU WON",If(I4=0,"WE TIED","I WON")))
E3=If(IsNA(I4),"1=SCISSORS","")
#                        12345678901234
D4=If(IsNA(I4),"2=ROCK","Clear column A")
#                  12345678901234
E4=If(IsNA(I4),""," to play again")

# computer move computation
B1=If(IsNA(A1),"",F4)
B2=If(Or(IsNA(B1),IsNA(A2)),"",G4)
B3=If(Or(IsNA(B2),IsNA(A3)),"",H4)

# win computation
# too complex for Workslate, so break it up
#C1=If(IsNA(A1),"",If(And(A1=0,B1=2),1,If(And(A1=2,B1=0),-1,If(A1>B1,1,If(B1>A1,-1,0)))))
C1=If(IsNA(A1),"",If(And(A1=0,B1=2),1,If(And(A1=2,B1=0),-1,I1)))
C2=If(IsNA(A2),"",If(And(A2=0,B2=2),1,If(And(A2=2,B2=0),-1,I2)))
C3=If(IsNA(A3),"",If(And(A3=0,B3=2),1,If(And(A3=2,B3=0),-1,I3)))

# offscreen columns

# really pseudo RNG
F1=Mod(Int(E1~$~127),65535)
F2=Mod(E1+Int(F1~%~511),65535)
F3=Mod(F1+Int(F2~$~256),65535)
F4=Mod(F3,3)

G1=Mod(F1+Int(E1~$~127),65535)
G2=Mod(F2+Int(F1~%~511),65535)
G3=Mod(F3+Int(F2~$~256),65535)
G4=Mod(G3,3)

H1=Mod(G1+Int(E1~$~127),65535)
H2=Mod(G2+Int(F1~%~511),65535)
H3=Mod(G3+Int(F2~$~256),65535)
H4=Mod(H3,3)

I1=If(A1>B1,1,If(B1>A1,-1,0))
I2=If(A2>B2,1,If(B2>A2,-1,0))
I3=If(A3>B3,1,If(B3>A3,-1,0))
I4=If(Or(IsNA(C1),IsNA(C2),IsNA(C3)),"",Total(C1...C3))
