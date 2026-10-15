[English](BDR-0001-explicit-replacement-intent.md) · [简体中文](BDR-0001-explicit-replacement-intent.zh-CN.md)

# BDR-0001: Separate showing a result from replacing directly

Status: Accepted. Source: the user's new request "translate and then replace directly" and the updated product definition.

## Decision

Plain translate and polish show the result first; text is written back only when the user clicks Replace. The separate "Translate and Replace" entry authorizes this run to write back directly once generation succeeds, with no further confirmation.

Both kinds of write-back share the same write-back conditions: write-back is refused only when there is no owning app, no Accessibility permission, or the owning app cannot be brought to the front. The selection content is no longer compared. A request that was cancelled or superseded by a newer operation must not write back late. History does not keep write-back permission.

## Consequences

Direct replacement does not turn every translation into an automatic write-back. Study recommendations do not block write-back, and a translation that was generated successfully but failed to replace still goes into history.
