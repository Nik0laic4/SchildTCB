/*
 * Copyright (C) 2026 Ирганов А.Н. Все права защищены.
 * Данный исходный код является объектом интеллектуальной собственности.
 * Разработано в научно-исследовательских и учебно-образовательных целях.
 * Проект имеет статус ограниченного распространения; публикация в открытых
 * репозиториях и передача третьим лицам без согласия автора не допускаются.
 */

/* =============================================================================
 * Schild TCB — seL4 syscall assembly stubs (x86_64, CONFIG_SYSCALL)
 *
 * ABI contract:
 *   - RSP saved in RBX before syscall (kernel reads user RSP from RBX)
 *   - RBX CALLEE-SAVED → we preserve it on the stack (push/pop) across syscall
 *   - syscall clobbers: RCX, R11
 *   - RSP restored from RBX after syscall (kernel may have modified RBX)
 * =============================================================================
 */

.section .text

.globl schild_sel4_yield
schild_sel4_yield:
    pushq   %rbx      /* save caller RBX on the stack                  */
    movq    %rsp, %rbx       /* RBX = user RSP for kernel                  */
    movq    $-11, %rdx       /* seL4_SysYield = -11                        */
    syscall
    movq    %rbx, %rsp       /* restore RSP from kernel-modified RBX       */
    popq    %rbx       /* restore caller RBX from the stack            */
    ret

/* Wait — blocking receive WITHOUT a reply object (seL4_SysWait = -9, MCS).
 * Used by the root task to block on the fault endpoint (faults are delivered
 * as plain Sends, so no reply object is required).  Returns the sender badge
 * in RAX and the message info in RDX, capturing MR[0..3] like Recv. */
.globl schild_sel4_wait
schild_sel4_wait:
    /* RBX is callee-saved; we preserve it on the stack because the
     * kernel ABI carries the user RSP in RBX across syscall. */
    pushq   %rbx       /* save caller RBX on the stack                  */
    movq    %rsp, %rbx        /* RBX = user RSP for kernel                   */
    xorq    %rsi, %rsi        /* empty message info (receive)                */
    movq    $-9, %rdx         /* seL4_SysWait = -9 (MCS)                     */
    syscall
    /* Capture MR[0..3]: on x86_64 these are delivered in R10/R8/R9/R15,
     * NOT in the IPC buffer (only MR[4+] go to the buffer). */
    movq    %r10, schild_recv_mr+0(%rip)
    movq    %r8,  schild_recv_mr+8(%rip)
    movq    %r9,  schild_recv_mr+16(%rip)
    movq    %r15, schild_recv_mr+24(%rip)
    movq    %rbx, %rsp        /* restore RSP                                 */
    movq    %rdi, %r11        /* badge → R11 (kernel-preserved volatile)     */
    movq    %rsi, %rdx        /* info → RDX (2nd return)                     */
    popq    %rbx        /* restore caller RBX from the stack            */
    movq    %r11, %rax        /* badge → RAX (return value)                  */
    ret

/* Recv — blocking receive WITH a reply object (seL4_SysRecv = -7, MCS).
 * C: i64 schild_sel4_recv(u64 src, u64 reply).
 *   RDI = src (endpoint/notification cap), RSI = reply (reply-object cap).
 * The reply cap is passed in R12 (seL4 replyRegister on MCS) and must be a
 * valid reply-object cap: on a Call the kernel stores the caller's reply
 * capability into it.  Returns badge in RAX, info in RDX. */
.globl schild_sel4_recv
schild_sel4_recv:
    pushq   %rbx       /* save caller RBX                                 */
    pushq   %r12       /* save caller R12 (reply register)                */
    movq    %rsp, %rbx        /* RBX = user RSP for kernel                */
    movq    %rsi, %r12        /* reply cap (RSI) → R12 (replyRegister)    */
    xorq    %rsi, %rsi        /* empty message info (receive)             */
    movq    $-7, %rdx         /* seL4_SysRecv = -7                        */
    syscall
    /* Capture MR[0..3] (see Wait for the ABI rationale). */
    movq    %r10, schild_recv_mr+0(%rip)
    movq    %r8,  schild_recv_mr+8(%rip)
    movq    %r9,  schild_recv_mr+16(%rip)
    movq    %r15, schild_recv_mr+24(%rip)
    movq    %rbx, %rsp        /* restore RSP                              */
    movq    %rdi, %r11        /* badge → R11 (volatile, kernel-preserved) */
    movq    %rsi, %rdx        /* info → RDX (2nd return)                  */
    popq    %r12        /* restore caller R12                              */
    popq    %rbx        /* restore caller RBX                              */
    movq    %r11, %rax        /* badge → RAX (return value)               */
    ret

/* ReplyRecv — reply to the caller, then block on the next receive in one
 * syscall (seL4_SysReplyRecv = -2, MCS).  There is NO standalone Reply in MCS.
 * C: i64 schild_sel4_replyrecv(u64 src, u64 info, u64 reply).
 *   RDI = src, RSI = info, RDX = reply (reply-object cap → R12).
 * The reply words travel in the hardware message registers, and after the
 * receive phase the next sender's badge/info/MRs are captured like Recv. */
.globl schild_sel4_replyrecv
schild_sel4_replyrecv:
    pushq   %rbx       /* save caller RBX                                 */
    pushq   %r12       /* save caller R12 (reply register)                */
    movq    %rdx, %r12        /* reply cap (RDX) → R12 (replyRegister)    */
    movq    %rsp, %rbx        /* RBX = user RSP for kernel                */
    /* Load reply MR[0..3] from schild_reply_mr (x86_64: R10/R8/R9/R15). */
    movq    schild_reply_mr+0(%rip), %r10
    movq    schild_reply_mr+8(%rip), %r8
    movq    schild_reply_mr+16(%rip), %r9
    movq    schild_reply_mr+24(%rip), %r15
    movq    $-2, %rdx         /* seL4_SysReplyRecv = -2 (MCS)             */
    syscall
    /* Capture MR[0..3] of the NEXT received message (recv phase). */
    movq    %r10, schild_recv_mr+0(%rip)
    movq    %r8,  schild_recv_mr+8(%rip)
    movq    %r9,  schild_recv_mr+16(%rip)
    movq    %r15, schild_recv_mr+24(%rip)
    movq    %rbx, %rsp        /* restore RSP                              */
    movq    %rdi, %r11        /* badge → R11 (volatile, kernel-preserved) */
    movq    %rsi, %rdx        /* info → RDX (2nd return)                  */
    popq    %r12        /* restore caller R12                              */
    popq    %rbx        /* restore caller RBX                              */
    movq    %r11, %rax        /* badge → RAX (return value)               */
    ret

/* ReplyOnly — invoke the reply cap WITHOUT a following receive (MCS).
 * Used by the NetServer crash-containment test to reply first, then fault on
 * an unmapped page.  The reply cap is invoked via SysSend (-5): the kernel
 * dispatches cap_reply_cap to performInvocation_Reply (doReplyTransfer).
 * C: i64 schild_sel4_reply_only(u64 reply, u64 info).
 *   RDI = reply (reply-object cap), RSI = info. */
.globl schild_sel4_reply_only
schild_sel4_reply_only:
    pushq   %rbx
    movq    %rsp, %rbx
    movq    schild_reply_mr+0(%rip), %r10
    movq    schild_reply_mr+8(%rip), %r8
    movq    schild_reply_mr+16(%rip), %r9
    movq    schild_reply_mr+24(%rip), %r15
    movq    $-5, %rdx         /* seL4_SysSend = -5 (invoke reply cap)      */
    syscall
    movq    %rbx, %rsp
    popq    %rbx
    ret

.globl schild_sel4_debug_putchar
schild_sel4_debug_putchar:
    pushq   %rbx       /* save caller RBX on the stack                  */
    movq    %rsp, %rbx        /* RBX = user RSP for kernel                  */
    movq    $-12, %rdx        /* seL4_SysDebugPutChar = -12                 */
    syscall
    movq    %rbx, %rsp        /* restore RSP from kernel-modified RBX       */
    popq    %rbx        /* restore caller RBX from the stack            */
    ret

/* Pause hint — unprivileged spin-loop hint for Ring 3 */
.globl schild_pause
schild_pause:
    pause
    ret

/* ─── MR capture/send globals ───────────────────────────────────────────────
 * seL4 x86_64 delivers MR[0..3] in R10/R8/R9/R15 (only MR[4+] hit the IPC
 * buffer).  These globals let C code read received MRs and stage reply MRs.
 */
.section .bss
.align 8
.globl schild_recv_mr
schild_recv_mr:
    .space 32
.globl schild_reply_mr
schild_reply_mr:
    .space 32
.globl schild_call_mr
schild_call_mr:
    .space 32

.section .text

/* NBWait — non-blocking receive WITHOUT a reply object (seL4_SysNBWait = -10,
 * MCS).  Used by the root task to poll the e1000e IRQ notification.  Returns
 * badge in RAX (0 means nothing pending) and info in RDX. */
.globl schild_sel4_nbwait
schild_sel4_nbwait:
    pushq   %rbx       /* save caller RBX on the stack                  */
    movq    %rsp, %rbx        /* RBX = user RSP for kernel                   */
    xorq    %rsi, %rsi        /* empty message info (receive)                */
    movq    $-10, %rdx        /* seL4_SysNBWait = -10 (MCS)                  */
    syscall
    /* Capture MR[0..3] (see Wait for the ABI rationale). */
    movq    %r10, schild_recv_mr+0(%rip)
    movq    %r8,  schild_recv_mr+8(%rip)
    movq    %r9,  schild_recv_mr+16(%rip)
    movq    %r15, schild_recv_mr+24(%rip)
    movq    %rbx, %rsp        /* restore RSP                                 */
    movq    %rdi, %r11        /* badge → R11 (volatile, kernel-preserved)    */
    movq    %rsi, %rdx        /* info → RDX (2nd return)                     */
    popq    %rbx        /* restore caller RBX from the stack            */
    movq    %r11, %rax        /* badge → RAX (return value)                  */
    ret

.section .note.GNU-stack,"",@progbits
