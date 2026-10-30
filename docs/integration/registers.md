# Firewall MMIO registers

`firewall_mmio` has a trusted, immediate CPU-local interface. Each accepted transfer is one cycle of `bus_valid`; reads and `bus_error` are combinational and writes take effect at the rising edge. There is no wait signal. The bus must supply aligned word addresses and `bus_wstrb=0xf` for every write. Invalid accesses return an error, have no side effects except recording an error, and read as zero. Outputs are inactive during reset.

| Offset | Access | Meaning |
|---|---|---|
| 0x00 | R | ID `0x534f4301` |
| 0x04 | R | STATUS: bit 0 mailbox busy, bit 1 session/update busy, bit 2 commit pending, bit 8 SHADOW |
| 0x08 | W | CMD: 1 BEGIN, 2 WRITE_ENTRY, 3 COMMIT |
| 0x0c | R/W1C | ERR: bit 0 invalid access or value, bit 1 invalid command or ordering, bit 2 command while mailbox busy |
| 0x10 | R/W | INDEX, 0–3 |
| 0x14 | R/W | BASE, inclusive byte address |
| 0x18 | R/W | LIMIT, inclusive byte address |
| 0x1c | R/W | PERM: bit 0 enable, bit 1 read, bit 2 write |
| 0x20 | R | COMMIT_SEQ, increments on actual commit acknowledgment |
| 0x24 | R | WRITTEN_MASK, one bit per accepted entry in the current or most recent session |
| 0x28 | R | CMD_SEQ, increments on each underlying begin, entry, or commit handshake |

Reserved bits in INDEX and PERM must be zero. Counters wrap modulo 2^32. Reset clears staging, counters, errors, mailbox and session; it abandons pending operations as described in the firewall specification. ERR is sticky; writing ones clears selected bits, with a simultaneous error taking precedence.

BEGIN reserves a session immediately and queues its underlying handshake. WRITE_ENTRY is legal only in a session; it snapshots all four staging registers into the one-entry mailbox. Staging can be changed while the entry is pending without changing the snapshot. The mask changes only after the firewall accepts the entry; rewrites are allowed. COMMIT is legal only once all four mask bits are set and remains pending through the actual acknowledgment, including an arbitrarily long traffic drain. A second command while the mailbox is occupied fails immediately; an invalid command is never queued, so software can correct its ordering. Reads and staging writes remain responsive while busy. Poll STATUS and compare sequence counters; acceptance of the CPU write is not proof of firewall acceptance or policy activation. No new session is permitted until commit acknowledgment.
