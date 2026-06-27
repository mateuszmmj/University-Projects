global arithmetic_sequence

section .text
; Argumenty funkcji:
; rdi - uint64_t const *A_0
; rsi - uint64_t const *A_1
; rdx - uint64_t *A_k
; rcx - size_t n
; r8  - size_t k

; Stosujemy trik pozwalajacy nam miec zawsze nieujemne k. 
; Jeżeli k jest ujemne to korzystamy z rownosci:
; A_k = k(A_1 - A_0) + A_0 = -|k|(A_1 - A_0) + A_0
; = |k|(A_0 - A_1) + A_0 = (|k| + 1)(A_0 - A_1) + A_1
; Co pozwala nam w takiej sytuacji zamienic A_0 i A_1 
; i liczyc |k|+1 wyraz ciągu B gdzie B_0 = A_1, B_1 = A_0

; Rejestru r9 używamy do przetrzymywania A_k aby zwolnic rdx
; Rejestr rcx używany jest w petli jako licznika
; A_other = (k < 0 ? A_0 : A_1), A_start = (k < 0 ? A_1, A_0)


arithmetic_sequence:
    mov r9, rdx         ; Przesuwamy bo rdx bedziemy uzywac do mul.

    xor r10d, r10d      ; W r10 bedzie carry z mnozenia i dodawnaia A_start.
    xor r11d, r11d      ; W r11 bedzie carry z odejmowania.

    test r8, r8         ; SF = 1 jezeli k < 0.
    jns .petla          ; Skaczemy jezeli k >= 0.
	
    ; Rozpatrzenie sytuacji gdy k < 0
    xchg rsi, rdi       ; A_other = A_0, A_start = A_1
    neg r8
    inc r8              ; Po tych 2 instrukcjach k -> -k + 1.

; W tej petli wypelniamy A_k (r9) wynikiem.
.petla:
    add r11, r11        ; Odtworzenie borrow z odejmowania w CF.
    
    mov rax, [rsi]      ; rax = A_other
    sbb rax, [rdi]      ; rax = A_other - A_start - borrow
    sbb r11, r11        ; Zapisanie borrow do r11.
    
    mul r8              ; rdx:rax <- k * (A_other - A_start)
    
    add rax, r10        ; rdx:rax <- k * (A_other - A_start) + OF
    adc rdx, 0
    
    add rax, [rdi]      ; rdx:rax <- k * (A_other - A_start) + OF + A_start
    adc rdx, 0
    
    mov r10, rdx        ; Zapisanie overflowu w r10.
    mov [r9], rax       ; Zapisanie wyniku w miejscu docelowym.

    ; Przesuniecie wskaznikow.
    add rsi, 8
    add rdi, 8
    add r9, 8
   	
    dec rcx
    jnz .petla

; Nizej wypelniamy rdx:rax.
.reszta:
    mov rcx, [rsi - 8]
    sar rcx, 63         ; rcx = s1 (znak A_other)

    mov rax, [rdi - 8]
    sar rax, 63         ; rax = s0 (znak A_start)

    cqo                 ; Rozszerzamy na rdx znak rax, czyli s0.

    sub rcx, rax
    add rcx, r11        ; rcx = s1 - s0 - borrow

    and rcx, r8         ; rcx = k if rcx = -1 else rcx = 0

    ; Dodajemy overflow z petli.
    add rax, r10
    adc rdx, 0		

    ; Odejmujemy k jeżeli A_other - A_start < 0.
    sub rax, rcx
    sbb rdx, 0

    ret
