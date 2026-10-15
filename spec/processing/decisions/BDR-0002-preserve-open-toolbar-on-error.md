[English](BDR-0002-preserve-open-toolbar-on-error.md) · [简体中文](BDR-0002-preserve-open-toolbar-on-error.zh-CN.md)

# BDR-0002: Errors keep an expanded toolbar open

Status: Accepted. Source: the user confirmed that a problem before opening uses a compact notice, and an error after opening keeps the toolbar.

## Decision

While the toolbar has not expanded yet, a problem that blocks the operation is shown as a compact notice, with the matching inline settings or recovery entry.

Once the toolbar has expanded, errors are shown in the content area and the window does not collapse. The user can keep reading the source text and any results that are still usable, and choose the applicable action: settings, retry, or copy.

## Rationale

When the operation is blocked before opening, there is no need to show a full processing interface that cannot be used. When an error happens after opening, the reading and working context the user already has should be kept.

## Consequences

The same error can be presented differently depending on whether the toolbar has expanded. Error presentation does not change the replacement authorization or validity requirements for the original selection.
