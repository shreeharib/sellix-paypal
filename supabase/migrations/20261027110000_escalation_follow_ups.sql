-- Questions the customer is waiting on: the agent holds instead of guessing, and the customer
-- gets one "still checking" follow-up if the merchant hasn't answered in time (plan 1.6).
alter table escalations
    add column customer_waiting boolean not null default false,
    add column followed_up_at timestamptz;

create index escalations_waiting_idx on escalations (created_at)
    where status = 'open' and customer_waiting and followed_up_at is null;
