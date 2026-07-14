# Notification Service Design

**Date:** 2026-07-13
**Status:** Draft

## Purpose

A small service that sends account notifications (email in v1) when domain
events occur.

## Requirements

- Events are consumed from the `events` queue.
- Duplicate events are removed before sending.
- A notification is sent within 60 seconds of event arrival.
- Retry behavior follows the policy in the Error Handling section.

## Delivery rules

Notifications for a given user are sent at most once per 10 minutes; excess
notifications are dropped.

## Batching

To reduce noise, notifications for a given user are batched: every
notification is held for 15 minutes and merged with later ones before a
single send.

## Storage

Sent notifications are recorded with `{user_id, event_id, sent_at}` and kept
for 90 days.
