-- Migration: 20261107010000_escalation_suggested_answers.sql
-- Goal: the agent's suggested answers to a question for the shop owner are data, not text glued
--       onto the question, so the merchant app can show them as one-tap replies.

ALTER TABLE escalations
    ADD COLUMN IF NOT EXISTS suggested_answers TEXT[] NOT NULL DEFAULT '{}';
