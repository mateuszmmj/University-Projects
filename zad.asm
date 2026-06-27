bits 64
default rel

global _start

; --------------------------------------------------------------------------
; Linux x86-64 syscall numbers
; --------------------------------------------------------------------------

%define SYS_read            0
%define SYS_write           1
%define SYS_mmap            9
%define SYS_munmap          11
%define SYS_mremap          25
%define SYS_exit            60

; --------------------------------------------------------------------------
; Syscall flags
; --------------------------------------------------------------------------

%define PROT_READ           1
%define PROT_WRITE          2

%define MAP_PRIVATE         2
%define MAP_ANONYMOUS       32

%define MREMAP_MAYMOVE      1

; --------------------------------------------------------------------------
; Standard file descriptors
; --------------------------------------------------------------------------

%define STDIN               0
%define STDOUT              1

; --------------------------------------------------------------------------
; Buffer sizes
; --------------------------------------------------------------------------

%define INPUT_INIT_CAP      65536
%define OUT_CAP             65536

; --------------------------------------------------------------------------
; Alphabet information
; Symbols are ASCII characters 33-126.
; --------------------------------------------------------------------------

%define FIRST_SYMBOL        33
%define LAST_SYMBOL         126
%define ALPHABET_SIZE       94

; Special value for symbols that never disappear.
%define DIE_INF             0xffffffffff
; --------------------------------------------------------------------------
; Dynamic stack frame layout
; ptr - address of currently processed byte in some rule
; end - end of the currently processed rule
; rem - remaining number of iterations 
; --------------------------------------------------------------------------

%define FRAME_SIZE          32
%define FRAME_PTR           0
%define FRAME_END           8
%define FRAME_REM           16
%define FRAME_EXTRA         24

%define STACK_INIT_FRAMES   4096
%define STACK_INIT_BYTES    (STACK_INIT_FRAMES * FRAME_SIZE)

%define NEWLINE             10

; --------------------------------------------------------------------------
; Checks if the symbol is in the vald range.
; %1 - symbol address, %2 - name of the error exit label
; --------------------------------------------------------------------------
%macro CHECK_SYMBOL 2
    cmp     %1, FIRST_SYMBOL
    jb      %2

    cmp     %1, LAST_SYMBOL
    ja      %2
%endmacro

section .bss
; --------------------------------------------------------------------------
; It holds the exit value for the program.
; --------------------------------------------------------------------------
exit_value:                 resd 1
; --------------------------------------------------------------------------
; Dynamic input buffer.
;
; input_base = pointer returned by mmap
; input_len = number of bytes already read
; input_cap = allocated size in bytes
; --------------------------------------------------------------------------

input_base:                 resq 1
input_len:                  resq 1
input_cap:                  resq 1

; --------------------------------------------------------------------------
; Dynamic generator stack.
;
; stack_base = pointer returned by mmap
; stack_size = number of currently used bytes
; stack_cap = capacity measured in bytes allocated
; --------------------------------------------------------------------------

stack_base:                 resq 1
stack_size:                 resq 1
stack_cap:                  resq 1

; --------------------------------------------------------------------------
; Output buffer.
;
; out_buf stores bytes before flushing with SYS_write.
; out_pos is the current number of bytes in out_buf.
; --------------------------------------------------------------------------

out_pos:                    resq 1
out_buf:                    resb OUT_CAP

; --------------------------------------------------------------------------
; Parsed command line argument.
;
; iterations = n from ./discrete_fractal n
; Stored as qword for convenience, although valid range is uint32_t.
; --------------------------------------------------------------------------

iterations:                 resq 1

; --------------------------------------------------------------------------
; Initial string, i.e. the first input line.
;
; The string is not copied. initial_ptr points into input_base.
; Initial_len does not include the newline.
; --------------------------------------------------------------------------

initial_ptr:                resq 1
initial_len:                resq 1

; --------------------------------------------------------------------------
; Replacement rules.
;
; idx = symbol - FIRST_SYMBOL
;
; rule_exists[idx] = 0/1
; rule_ptr[idx] = pointer to RHS inside input_base
; rule_len[idx] = length of RHS
;
; Important:
; no rule => symbol maps to itself
; existing empty rule => symbol maps to empty string
; --------------------------------------------------------------------------

rule_exists:                resb ALPHABET_SIZE
rule_ptr:                   resq ALPHABET_SIZE
rule_len:                   resq ALPHABET_SIZE

; --------------------------------------------------------------------------
; Disappearing-symbol analysis.
;
; die[idx] = minimal k such that h^k(symbol) = empty string,
; or DIE_INF if the symbol never fully disappears.
; --------------------------------------------------------------------------

die:                        resq ALPHABET_SIZE

; --------------------------------------------------------------------------



; --------------------------------------------------------------------------

has_cycle:                  resb ALPHABET_SIZE
cycle_len:                  resq ALPHABET_SIZE
seen:                       resb ALPHABET_SIZE
tab:                        resq ALPHABET_SIZE

; --------------------------------------------------------------------------

section .text

_start:
    ; Setting the exit value to 1 till the input is validated
    mov dword[exit_value], 1

    ; Moving number of arguments do rax.
    mov rax, [rsp]                  

    ; Checking if the number of arguments is 2, if not exiting. 
    cmp rax, 2                      
    jne error_exit_0            
    
    ; Moving unparsed n to rsi.
    mov rsi, [rsp + 16]         

    call parse_n            

    call alloc_input_buffer

    call read_input

    call parse_input 

    call alloc_stack

    call compute_die

    call compute_cycle

    call generate_output

exit:
    ; Setting the last char to be written as '\n'.
    mov al, NEWLINE
    call put_char
    call flush_buffer

    ; Setting correct exit_value
    mov dword[exit_value], 0

; For when the dynamic stack is allocated
error_exit_2:         
    mov eax, SYS_munmap
    mov rdi, qword[stack_base]                      ; addr
    mov rsi, qword[stack_cap]                       ; length

    ; Making sure stack was allocated
    test rdi, rdi
    jz error_exit_1

    syscall

    cmp rax, -4095
    jae error_exit_0
; For when only the input buffer is allocated
error_exit_1:
    mov eax, SYS_munmap
    mov rdi, qword[input_base]                      ; addr
    mov rsi, qword[input_cap]                       ; length

    ; Making sure input buffer was allocated.
    test rdi, rdi
    jz error_exit_0

    syscall

; For when no memory is allocated using mmap
error_exit_0:
    mov eax, SYS_exit
    mov edi, dword[exit_value]
    syscall


; --------------------------------------------------------------------------
;
;                               FUNCTIONS
;
; --------------------------------------------------------------------------



; --------------------------------------------------------------------------
; DESCRIPTION:
; Parses argc[1] to a number and checks its validity.
; OUTPUT:
; [iterations] = n
; DESTROYS:
; rax, rcx, rsi, rdx
; --------------------------------------------------------------------------
parse_n:
    ; Used to store result.
    xor eax, eax                    
    ; Used to store the current byte/digit.
    xor ecx, ecx                    

    movzx ecx, byte[rsi] 
    
    ; Checking if the first byte isnt '\0'.
    test cl, cl                     
    jz error_exit_0

    ; Jumping into the loop if the first char isnt '0'.
    cmp cl, '0'
    jne .loop

    ; If the first char is '0' and the second one isn't '\0' exiting.
    cmp byte[rsi + 1], 0
    jne error_exit_0
    
    ; n = 0
    jmp .done
.loop:
    movzx ecx, byte[rsi]

    ; Checking if there's anything else to parse.
    test cl, cl                     
    jz .done

    ; Checking if the byte is valid, i.e. contains a digit in range '0'-'9'.
    cmp cl, '0'             
    jb error_exit_0

    cmp cl, '9'
    ja error_exit_0

    ; Now cl stores the numeric value of the digit, not the ASCII one.
    sub cl, '0'                             

    ; rax -> 10*rax + rcx
    lea rax, [rax + rax*4]
    lea rax, [rcx + rax*2]

    ; Checking if rax < 2^32.
    mov edx, -1                             
    cmp rax, rdx                            
    ja error_exit_0
    
    inc rsi
    jmp .loop

.done:
    mov qword[iterations], rax
    ret 



; --------------------------------------------------------------------------
; DESCRIPTION:
; Allocates INPUT_INIT_CAP bytes for the input buffer.
; OUTPUT:
; [input_base] = pointer to beginning of the buffer
; [input_len] = 0
; [input_cap] = INPUT_INIT_CAP
; DESTROYS:
; rax, rdi, rsi, rdx, r10, r8, r9
; --------------------------------------------------------------------------
alloc_input_buffer:
    ; Preparing registers for a mmap syscall.
    mov eax, SYS_mmap
    xor edi, edi                                    ; addr = NULL
    mov esi, INPUT_INIT_CAP                         ; length
    mov edx, PROT_READ | PROT_WRITE                 ; prot
    mov r10d, MAP_PRIVATE | MAP_ANONYMOUS           ; flags
    mov r8, -1                                      ; fd = -1
    xor r9d, r9d                                    ; offset = 0
    
    syscall

    cmp rax, -4095
    jae error_exit_0

    mov [input_base], rax
    mov qword[input_len], 0
    mov qword[input_cap], INPUT_INIT_CAP

    ret



; --------------------------------------------------------------------------
; DESCRIPTION:
; Doubles the size of the input buffer.
; OUTPUT:
; [input_base] = possibly changed 
; [input_cap] = double the previous size
; REQUIRES:
; Previous usage of alloc_input_buffer.
; DESTROYS:
; rax, rsi, rdi, rdx, r10, rcx, r11
; --------------------------------------------------------------------------
grow_input_buffer:
    ; Preparing regusters for a mremap syscall.
    mov eax, SYS_mremap
    mov rdi, qword[input_base]                      ; old_adress
    mov rsi, qword[input_cap]                       ; old size
    mov rdx, qword[input_cap]                        
    shl rdx, 1                                      ; new size = 2 * old size
    mov r10d, MREMAP_MAYMOVE                        ; flags

    syscall

    cmp rax, -4095
    jae error_exit_1

    mov qword[input_base], rax
    mov qword[input_cap], rdx
    
    ret



; --------------------------------------------------------------------------
;                       INPUT PARSING FUNCTIONS
; --------------------------------------------------------------------------

; --------------------------------------------------------------------------
; DESCRIPTION:
; Reads all stdin into a dynamic buffer.
; OUTPUT:
; [input_base] = pointer to the buffer
; [input_len] = number of bytes read
; [input_cap] = size of the buffer (may change)
; REQUIRES:
; Previous usage of alloc_input_buffer
; DESTROYS:
; rax. rsi, rdi, rdx, r10, rcx, r11
; --------------------------------------------------------------------------
read_input:
.loop:
    mov rax, qword[input_len];

    ; Checking if the buffer is full and we need to enlarge it.
    cmp rax, qword[input_cap];
    jne .not_full

    call grow_input_buffer

.not_full:
    ; Preparing for a read syscall.
    mov eax, SYS_read
    mov rsi, qword[input_base]
    add rsi, qword[input_len]                       ; buf
    mov rdx, qword[input_cap]
    sub rdx, qword[input_len]                       ; count
    mov edi, STDIN                                  ; fd

    syscall
    
    ; Checking for syscall error.
    cmp rax, -4095
    jae error_exit_1
    
    ; Checking if there's anything else to read.
    test rax, rax
    jz .done

    ; Increasing input_len by the amount of data read by a syscall.
    add qword[input_len], rax
    jmp .loop

.done:
    ret





; --------------------------------------------------------------------------
; DESCRIPTION:
; Places a char into a buffer.
; OUTPUT:
; Fills rule_ptr, rule_exists, rule_len, input_len, input_ptr.
; Also checks the validity of the input.
; DESTROYS:
; rax, rdx, rbx, rcx, r11, rdi
; --------------------------------------------------------------------------
parse_input:
    mov r11, qword[input_len]                       
    mov rbx, qword[input_base]                      ; current byte
    xor ecx, ecx                                    ; length of line

    ; Checking if the input_len > 0.
    test r11, r11
    jz error_exit_1

    ; RAX now holds the address of the last '\n'.
    add r11, rbx                                    ; r11 - 1 = last byte

    ; Making sure the last byte is '\n'.
    cmp byte[r11 - 1], NEWLINE
    jne error_exit_1

    ; Setting the pointer to the beginning of the initial text.
    mov qword[initial_ptr], rbx

.first_line_loop:
    movzx eax, byte[rbx]
    inc rbx

    ; We know there will be at least.
    cmp al, NEWLINE
    je .first_line_loop_end


    ; Updating length of line.
    inc rcx                                         

    CHECK_SYMBOL al, error_exit_1 

    jmp .first_line_loop


.first_line_loop_end:
    ; Setting the length of the initial text.
    mov qword[initial_len], rcx
    
    ; Checking if there are any rules to parse.
    cmp rbx, r11
    je .done

.parse_rule_symbol:
    movzx eax, byte[rbx]
    inc rbx

    CHECK_SYMBOL al, error_exit_1 
    
    sub eax, FIRST_SYMBOL

    ; Checking if the symbol already has a rule.
    lea rdi, [rule_exists] 
    cmp byte[rdi + rax], 1
    je error_exit_1

    ; Marking that a rule exists.
    mov byte[rdi + rax], 1

    ; Setting pointer to the rule.
    lea rdi, [rule_ptr]
    mov qword[rdi + rax*8], rbx

    ; Resetting rule_len counter.
    xor ecx, ecx
    
    ; Memorizing the rule char.
    mov rdx, rax                            

.parse_rule:
    movzx eax, byte[rbx] 
    inc rbx

    ; Check if the current char is the '\n', if yes end rule parsing.
    cmp eax, NEWLINE
    je .end_rule_parsing

    inc rcx

    CHECK_SYMBOL al, error_exit_1

    jmp .parse_rule

.end_rule_parsing:
    ; Setting rule length.
    lea rdi, [rule_len]  
    mov qword[rdi + rdx*8], rcx

    ; Check if there are any more rules to parse.
    cmp rbx, r11
    jne .parse_rule_symbol

.done:
    ret




; --------------------------------------------------------------------------
;                           OUTPUT BUFFER FUNCTIONS
; --------------------------------------------------------------------------

; --------------------------------------------------------------------------
; DESCRIPTION:
; Writes out the constents of the buffer to STDOUT.
; OUTPUT:
; out_pos = 0
; DESTROYS:
; rax, rdi, rsi, rdx, rcx, r11
; --------------------------------------------------------------------------
flush_buffer:
    ; Preparing for a syscall.
    mov rdx, qword[out_pos]                         ; bytes left
    
    ; Checking if there's anything to flush.
    test rdx, rdx
    jz .done
    
    lea rsi, [out_buf]                              ; write pointer

.loop:
    mov eax, SYS_write
    mov edi, STDOUT                                 ; fd

    syscall
    
    cmp rax, -4095
    jae error_exit_2

    ; To avoid infinite loop.
    test rax, rax
    jz error_exit_2
    
    ; Increasing the write pointer by the number of bytes written.
    add rsi, rax

    ; Looping only if there's anyhing more to write.
    sub rdx, rax
    jnz .loop

    mov qword[out_pos], 0
.done:
    ret


; --------------------------------------------------------------------------
; DESCRIPTION:
; Places a char into a buffer.
; INPUT:
; al - the byte to be written
; DESTROYS:
; rax, rdi, rsi, rdx, rcx, r11
; --------------------------------------------------------------------------
put_char:
    mov r11, qword[out_pos]                         ; current length
    lea rcx, [out_buf]                              ; buffer address
    
    ; Placing the byte inside the buffer.
    mov byte[rcx + r11], al                         
    
    ; Updating out_pos value.
    inc r11
    mov qword[out_pos], r11

    ; Checking if the buffer is full, if yes flushing it.
    cmp r11, OUT_CAP
    jne .done

    call flush_buffer

.done:
    ret




; --------------------------------------------------------------------------
;                       DYNAMIC STACK FUNCTIONS
; --------------------------------------------------------------------------

; --------------------------------------------------------------------------
; DESCRIPTION:
; Allocates INPUT_INIT_CAP bytes for the dynamic stack
; OUTPUT:
; [stack_base] = pointer to beginning of the buffer
; [stack_size] = 0
; [stack_cap] = INPUT_INIT_CAP
; DESTROYS:
; rax, rdi, rsi, rdx, r10, r8, r9
; --------------------------------------------------------------------------
alloc_stack:
    ; Preparing registers for a mmap syscall.
    mov eax, SYS_mmap
    xor edi, edi                                    ; addr = NULL
    mov esi, STACK_INIT_BYTES                       ; length
    mov edx, PROT_READ | PROT_WRITE                 ; prot
    mov r10d, MAP_PRIVATE | MAP_ANONYMOUS           ; flags
    mov r8, -1                                      ; fd = -1
    xor r9d, r9d                                    ; offset = 0
    
    syscall

    cmp rax, -4095
    jae error_exit_1

    mov [stack_base], rax
    mov qword[stack_size], 0
    mov qword[stack_cap], STACK_INIT_BYTES

    ret



; --------------------------------------------------------------------------
; DESCRIPTION:
; Doubles the size of the dynamic stack
; OUTPUT:
; [stack_base] = possibly changed 
; [stack_cap] = double the previous size
; REQUIRES:
; Previous usage of alloc_stack
; DESTROYS:
; rax, rsi, rdi, rdx, r10, rcx, r11
; --------------------------------------------------------------------------
grow_stack:
    ; Preparing regusters for a mremap syscall.
    mov eax, SYS_mremap
    mov rdi, qword[stack_base]                      ; old_adress
    mov rsi, qword[stack_cap]                       ; old size
    mov rdx, qword[stack_cap]                        
    shl rdx, 1                                      ; new size = 2 * old size
    mov r10d, MREMAP_MAYMOVE                        ; flags

    syscall

    cmp rax, -4095
    jae error_exit_2

    mov qword[stack_base], rax
    mov qword[stack_cap], rdx
    
    ret

; --------------------------------------------------------------------------
; DESCRIPTION:
; Pushes a frame onto the dynamic stack.
; INPUT:
; r13 = ptr
; r14 = end
; r15 = rem
; OUTPUT:
; [stack_size] += FRAME_SIZE 
; DESTROYS:
; rax, rsi, rdi, rdx, r10, rcx, r11
; PRESERVES:
; r13, r14, r15
; --------------------------------------------------------------------------
push_frame:
    ; Checking if there's enough space for one more push, if not
    ; then the stack size is doubled.
    mov rax, qword[stack_size]
    add rax, FRAME_SIZE 

    cmp rax, qword[stack_cap]
    jbe .has_space

    call grow_stack

.has_space:
    ; rax -> frame address
    mov rax, qword[stack_base]                      
    add rax, qword[stack_size]

    mov qword[rax + FRAME_PTR], r13
    mov qword[rax + FRAME_END], r14
    mov qword[rax + FRAME_REM], r15
    mov qword[rax + FRAME_EXTRA], 0

    add qword[stack_size], FRAME_SIZE
    ret

; --------------------------------------------------------------------------
; DESCRIPTION:
; Pops top frame from the dynamic stack and fills r13-r15 with its contents.
; OUTPUT:
; [stack_size] -= FRAME_SIZE
; r13 = ptr
; r14 = end
; r15 = rem
; DESTROYS:
; rax, r13, r14, r15
; --------------------------------------------------------------------------
pop_frame:
    mov rax, qword[stack_size]

    ; Making sure the stack isn't empty.
    cmp rax, FRAME_SIZE
    jb error_exit_2
    
    ; Updating stack_size
    sub rax, FRAME_SIZE
    mov qword[stack_size], rax

    ; rax -> ptr to the beginning of top frame
    add rax, qword[stack_base]

    ; Filling r13-r15 with the contents of the top element of stack.
    mov r13, qword[rax + FRAME_PTR]
    mov r14, qword[rax + FRAME_END]
    mov r15, qword[rax + FRAME_REM]

    ret





    
; --------------------------------------------------------------------------
; DESCRIPTION:
; Sets all die[i] with proper values. die[i] is set to the length, 
; defined as a number of vertices, on the possible walk starting on
; the i-th symbol. If the path can be arbitrairly long then die[i] = DIE_INF.
; OUTPUT:
; Fills die.
; DESTROYS:
; rax, rbx, rcx, rdx, rdi, r8, r9, r10, r11
; --------------------------------------------------------------------------
compute_die:
    mov r10, DIE_INF
    xor r8d, r8d                                    ; i = 0

; Sets all die[i] = (rule_exist[i] && !rule_len[i] ? 1 : DIE_INF)
.init_loop:
    cmp r8d, ALPHABET_SIZE
    jae .main_loop_prep
    
    ; Setting die[i] = DIE_INF
    lea rdi, [die]
    mov qword[rdi + r8*8], r10

    ; Checking if a rule exists, if it doesn't we don't cahnge die[i].
    lea rdi, [rule_exists]
    cmp byte[rdi + r8], 0
    je .init_next

    ; Checking if rule_len = 0, if yes we set die[i] = 1.
    lea rdi, [rule_len]
    cmp qword[rdi + r8*8], 0
    jne .init_next

    lea rdi, [die]
    mov qword[rdi + r8*8], 1

.init_next:
    inc r8d
    jmp .init_loop

; We loop for as long as anything gets changes in the main loop.
.main_loop_prep:
    xor r11d, r11d                                  ; changed = 0
    xor r8d, r8d                                    ; i = 0

.symbol_loop:
    cmp r8d, ALPHABET_SIZE
    jae .pass_done

    ; If die[i] != DIE_INF, it is already computed.
    lea rdi, [die]
    mov rax, qword[rdi + r8*8]
    cmp rax, r10
    jne .next_symbol

    ; If there is no rule, symbol never disappears.
    lea rdi, [rule_exists]
    cmp byte[rdi + r8], 0
    je .next_symbol

    ; rcx = rhs length
    lea rdi, [rule_len]
    mov rcx, qword[rdi + r8*8]

    ; rbx = rhs pointer
    lea rdi, [rule_ptr]
    mov rbx, qword[rdi + r8*8]

    xor r9d, r9d                                    ; max_die = 0

.rule_loop:
    test rcx, rcx
    jz .rule_all_finite

    ; eax = index of current rhs symbol
    movzx eax, byte[rbx]
    sub eax, FIRST_SYMBOL

    ; rax = die[current symbol]
    lea rdi, [die]
    mov rax, qword[rdi + rax*8]

    ; If die[current symbol] >= DIE_INF, we cannot compute this rule yet.
    cmp rax, r10
    jae .next_symbol

    ; max_die = max(max_die, rax)
    cmp rax, r9
    jbe .rule_next
    mov r9, rax

.rule_next:
    inc rbx
    dec rcx
    jmp .rule_loop

.rule_all_finite:
    ; die[i] = max_die + 1
    inc r9

    lea rdi, [die]
    mov qword[rdi + r8*8], r9

    ; Something changes so we loop again.
    mov r11b, 1

.next_symbol:
    inc r8d
    jmp .symbol_loop

.pass_done:
    ; Checking if anything was changes.
    test r11b, r11b
    jnz .main_loop_prep

.done:
    ret





; --------------------------------------------------------------------------

; --------------------------------------------------------------------------
compute_cycle:
    xor ecx, ecx                                    ; i = 0
    lea rdi, [seen]

.main_loop: ; finished

    ; Check if we seen this char was already seen.
    movzx edx, byte[rdi + rcx]
    test edx, edx
    jnz .next_symbol
    
    ; Check if byte has a rule of non-zero length.
    lea rsi, [rule_len]
    cmp qword[rsi + rcx*8], 0
    je .next_symbol

    ; Checking if the byte has an infinite lifetime.
    mov rbx, DIE_INF
    lea rsi, [die]
    cmp qword[rsi + rcx*8], rbx
    jne .next_symbol
    
    ; Setting pointer to the first element in tab
    lea rsi, [tab]

    ; Setting the pointer to the qword after the last element in tab
    mov r11, ALPHABET_SIZE * 8                     
    add r11, rsi


; This loop clears the tab.
.clear_tab: ; finished
    mov qword[rsi], 0

    add rsi, 8
    cmp rsi, r11
    jne .clear_tab

    xor edx, edx                                    ; dfs path length
    mov rax, rcx                                    ; curr element in dfs

.dfs_loop: ; finidhed
    inc edx
    
    ; Check if we seen this char was already seen.
    movzx r12d, byte[rdi + rax]
    test r12d, r12d
    jz .not_seen_dfs

    ; Checking if it was seen in this dfs, if not setting the tab value to the
    ; current length of the path.
    lea rsi, [tab]
    mov r12, qword[rsi + rax*8]
    
    ; There's a cycle iff the tab value is non-zero.
    test r12, r12
    jnz .found_cycle
    jmp .next_symbol

.not_seen_dfs:
    ; Setting seen to 1.
    mov byte[rdi + rax], 1

    ; Checking if the symbol has a rule, if not we skip it.
    lea rsi, [rule_len]
    cmp qword[rsi + rax*8], 0
    je .next_symbol

    ; Setting the pointer to first element in rule[rcx].
    lea rsi, [rule_ptr]
    mov r10, qword[rsi + rax*8]

    ; Setting the pointer to the qword after the last element in rule[rcx].
    lea rsi, [rule_len]
    mov r11, qword[rsi + rax*8]
    add r11, r10

    ; Setting tab value
    lea rsi, [tab]
    mov qword[rsi + rax*8], rdx

    xor r13d, r13d                                  ; next cycle element

.rule_loop: ; finished
    movzx r12d, byte[r10] 
    sub r12, FIRST_SYMBOL

    ; Checking if die[r12] == INF, if not then we ignore.
    lea rsi, [die]
    mov r14, qword[rsi + r12*8]
    mov rbx, DIE_INF
    cmp r14, rbx
    jne .rule_loop_next 
    
    add r12, FIRST_SYMBOL

    test r13, r13
    jnz .next_symbol

    mov r13, r12


.rule_loop_next: ; finished
    inc r10
    cmp r10, r11
    jne .rule_loop

.dfs_next:
    ; Checking if we found the next_symbol in dfs
    test r13, r13
    jz .next_symbol

    mov rax, r13
    sub rax, FIRST_SYMBOL
    jmp .dfs_loop
.found_cycle:
    ; The element which repeated is in rax.
    ; cycle length is edx - tab[rax]
    ; rdx -= tab[rax]  
    lea rsi, [tab]
    mov rbx, qword[rsi + rax*8]
    sub rdx, rbx

    ; traversing tab and for all values >= rbx we set cycle_length to rdx
    ; and mark has_cycle
    
    lea r10, [tab]
    xor r11d, r11d                                  ; j = 0

.set_cycle_values: ; finished
    cmp qword[r10 + r11*8], rbx
    jb .after_set
    
    lea rsi, [has_cycle]
    mov byte[rsi + r11], 1
    
    lea rsi, [cycle_len]
    mov qword[rsi + r11*8], rdx

.after_set:
    inc r11
    cmp r11, ALPHABET_SIZE
    jne .set_cycle_values

.next_symbol:
    inc ecx
    cmp rcx, ALPHABET_SIZE
    jne .main_loop

    ret

; --------------------------------------------------------------------------
; DESCRIPTION:
; Generates the final output and writes it to the output buffer.
; Uses dynamic stack for storing parent continuations.
;
; Current frame:
; r13 = ptr
; r14 = end
; r15 = rem
;
; DESTROYS:
; rax, rbx, rcx, rdx, rdi, rsi, r8, r9, r10, r11, r12, r13, r14, r15
; --------------------------------------------------------------------------
generate_output:
    ; Setting current frame to initial string.
    mov r13, qword[initial_ptr]
    mov r14, r13
    add r14, qword[initial_len]
    mov r15, qword[iterations]

.loop:
    ; If current frame is finished, return to parent or finish generation.
    cmp r13, r14
    jne .process_symbol

    ; If stack is empty, whole generation is finished.
    cmp qword[stack_size], 0
    je .done

    ; Restore parent continuation.
    call pop_frame
    jmp .loop

.process_symbol:
    ; Loading current symbol and moving ptr to the next byte.
    movzx eax, byte[r13]
    inc r13

    ; Saving ASCII value of the symbol.
    mov r8b, al

    ; r12 = local rem for this symbol.
    mov r12, r15

    ; If rem == 0, emit the symbol directly.
    test r12, r12
    jz .write_symbol

    ; r9 = idx = symbol - FIRST_SYMBOL.
    sub eax, FIRST_SYMBOL
    mov r9, rax

    ; If die[idx] <= rem, this symbol disappears completely.
    lea rdi, [die]
    cmp qword[rdi + r9*8], r12
    jbe .loop

    ; If there is no rule, the symbol maps to itself.
    lea rdi, [rule_exists]
    cmp byte[rdi + r9], 0
    je .write_symbol

    ; Try to use cycle optimization.
    lea rdi, [has_cycle]
    cmp byte[rdi + r9], 0
    je .expand_rule

    ; rcx = cycle_len[idx]
    lea rdi, [cycle_len]
    mov rcx, qword[rdi + r9*8]

    ; Defensive check, should not happen if has_cycle[idx] is correct.
    test rcx, rcx
    jz .expand_rule

    ; Use optimization only if rem >= ALPHABET_SIZE + cycle_len.
    mov rax, ALPHABET_SIZE
    add rax, rcx
    cmp r12, rax
    jb .expand_rule

    ; r12 = ALPHABET_SIZE + ((r12 - ALPHABET_SIZE) mod cycle_len)
    mov rax, r12
    sub rax, ALPHABET_SIZE
    xor edx, edx
    div rcx

    mov r12, ALPHABET_SIZE
    add r12, rdx

.expand_rule:
    ; We are going down into the rule, so save current parent continuation.
    ; We need r9 and r12 after push_frame, so preserve them on CPU stack.
    push r9
    push r12
    call push_frame
    pop r12
    pop r9

    ; New current frame is the RHS of the rule with rem - 1.
    lea rdi, [rule_ptr]
    mov r13, qword[rdi + r9*8]

    lea rdi, [rule_len]
    mov r14, r13
    add r14, qword[rdi + r9*8]

    mov r15, r12
    dec r15

    jmp .loop

.write_symbol:
    mov al, r8b
    call put_char
    jmp .loop

.done:
    ret


