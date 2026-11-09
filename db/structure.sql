--
-- PostgreSQL database dump
--

\restrict coachnarails

-- Dumped from database version 16.15
-- Dumped by pg_dump version 16.15 (Ubuntu 16.15-0ubuntu0.24.04.1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: client_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.client_status AS ENUM (
    'active',
    'suspended',
    'deactivated'
);


--
-- Name: coach_document_type; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.coach_document_type AS ENUM (
    'profile_photo',
    'national_id_front',
    'national_id_back',
    'certificate'
);


--
-- Name: coach_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.coach_status AS ENUM (
    'incomplete',
    'pending_review',
    'approved',
    'rejected',
    'suspended',
    'deactivated'
);


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: client_addresses; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.client_addresses (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    client_id uuid NOT NULL,
    label text DEFAULT 'Home'::text NOT NULL,
    latitude double precision NOT NULL,
    longitude double precision NOT NULL,
    area text,
    street text,
    building text,
    floor text,
    apartment text,
    notes text,
    is_default boolean DEFAULT false NOT NULL,
    deleted_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: client_health_profiles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.client_health_profiles (
    client_id uuid NOT NULL,
    date_of_birth date,
    gender text,
    height_cm numeric(5,1),
    weight_kg numeric(5,1),
    activity_level text,
    goal text,
    target_weight_kg numeric(5,1),
    allergies jsonb,
    avoided_foods jsonb,
    completed_at timestamp with time zone,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: client_refresh_tokens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.client_refresh_tokens (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    client_id uuid NOT NULL,
    token text NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: clients; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.clients (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    phone text NOT NULL,
    password_hash text NOT NULL,
    full_name text NOT NULL,
    status public.client_status DEFAULT 'active'::public.client_status NOT NULL,
    phone_verified_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: coach_documents; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.coach_documents (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    coach_id uuid NOT NULL,
    type public.coach_document_type NOT NULL,
    storage_key text NOT NULL,
    original_name text,
    mime_type text NOT NULL,
    size_bytes integer NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: coach_packages; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.coach_packages (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    coach_id uuid NOT NULL,
    name text NOT NULL,
    description text,
    price_piastres integer NOT NULL,
    duration_days integer NOT NULL,
    includes jsonb NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: coach_refresh_tokens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.coach_refresh_tokens (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    coach_id uuid NOT NULL,
    token text NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: coach_reviews; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.coach_reviews (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    subscription_id uuid,
    client_id uuid NOT NULL,
    coach_id uuid NOT NULL,
    rating integer NOT NULL,
    body text,
    status text DEFAULT 'pending'::text NOT NULL,
    hidden_reason text,
    hidden_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    decided_at timestamp with time zone,
    decided_by uuid,
    CONSTRAINT coach_reviews_body_length CHECK (((body IS NULL) OR ((char_length(body) >= 1) AND (char_length(body) <= 1000)))),
    CONSTRAINT coach_reviews_rating_range CHECK (((rating >= 1) AND (rating <= 5))),
    CONSTRAINT coach_reviews_status_valid CHECK ((status = ANY (ARRAY['pending'::text, 'visible'::text, 'rejected'::text, 'hidden'::text])))
);


--
-- Name: coaches; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.coaches (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    email text,
    phone text,
    password_hash text NOT NULL,
    full_name text NOT NULL,
    bio text,
    years_experience integer,
    status public.coach_status DEFAULT 'incomplete'::public.coach_status NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    phone_verified_at timestamp with time zone,
    profile_submitted_at timestamp with time zone,
    reviewed_at timestamp with time zone,
    rejection_reason text,
    average_rating numeric(2,1),
    review_count integer DEFAULT 0 NOT NULL,
    specialties jsonb DEFAULT '[]'::jsonb NOT NULL,
    commission_percent numeric(5,2)
);


--
-- Name: conversations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.conversations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    subscription_id uuid NOT NULL,
    last_message_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: messages; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.messages (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    conversation_id uuid NOT NULL,
    sender_type text NOT NULL,
    sender_id uuid NOT NULL,
    body text,
    attachment_key text,
    attachment_mime text,
    client_ref uuid,
    sent_at timestamp with time zone DEFAULT now() NOT NULL,
    read_at timestamp with time zone,
    CONSTRAINT messages_body_length CHECK (((body IS NULL) OR ((char_length(body) >= 1) AND (char_length(body) <= 2000)))),
    CONSTRAINT messages_body_or_attachment CHECK (((body IS NOT NULL) OR (attachment_key IS NOT NULL))),
    CONSTRAINT messages_sender_type_valid CHECK ((sender_type = ANY (ARRAY['client'::text, 'coach'::text])))
);


--
-- Name: notifications; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.notifications (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    recipient_type text NOT NULL,
    recipient_id uuid NOT NULL,
    type text NOT NULL,
    title text NOT NULL,
    body text NOT NULL,
    data jsonb DEFAULT '{}'::jsonb NOT NULL,
    read_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: payments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.payments (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    client_id uuid NOT NULL,
    purpose text NOT NULL,
    subscription_id uuid,
    order_id uuid,
    amount_piastres integer NOT NULL,
    provider text NOT NULL,
    method text,
    provider_ref text,
    status text NOT NULL,
    paid_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT payments_amount_positive CHECK ((amount_piastres > 0)),
    CONSTRAINT payments_purpose_valid CHECK ((purpose = ANY (ARRAY['subscription'::text, 'order'::text]))),
    CONSTRAINT payments_status_valid CHECK ((status = ANY (ARRAY['pending'::text, 'paid'::text, 'failed'::text, 'refunded'::text]))),
    CONSTRAINT payments_subscription_has_id CHECK (((purpose <> 'subscription'::text) OR (subscription_id IS NOT NULL)))
);


--
-- Name: phone_verifications; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.phone_verifications (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    phone text NOT NULL,
    code_hash text NOT NULL,
    purpose text DEFAULT 'signup'::text NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    attempts integer DEFAULT 0 NOT NULL,
    consumed_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    account_type text DEFAULT 'coach'::text NOT NULL
);


--
-- Name: plan_meal_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.plan_meal_items (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    plan_meal_id uuid NOT NULL,
    "position" integer NOT NULL,
    food_name text NOT NULL,
    quantity numeric(7,2) NOT NULL,
    unit text NOT NULL,
    preparation text,
    CONSTRAINT plan_meal_items_quantity_positive CHECK ((quantity > (0)::numeric))
);


--
-- Name: plan_meals; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.plan_meals (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    plan_id uuid NOT NULL,
    day_of_week integer,
    slot text NOT NULL,
    "position" integer NOT NULL,
    title text NOT NULL,
    spec_type text NOT NULL,
    kcal integer,
    protein_g integer,
    carbs_g integer,
    fat_g integer,
    notes text,
    CONSTRAINT plan_meals_day_valid CHECK (((day_of_week IS NULL) OR ((day_of_week >= 0) AND (day_of_week <= 6)))),
    CONSTRAINT plan_meals_slot_valid CHECK ((slot = ANY (ARRAY['breakfast'::text, 'lunch'::text, 'dinner'::text, 'snack'::text]))),
    CONSTRAINT plan_meals_spec_type_valid CHECK ((spec_type = ANY (ARRAY['by_targets'::text, 'by_food'::text])))
);


--
-- Name: plans; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.plans (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    subscription_id uuid NOT NULL,
    version integer NOT NULL,
    status text NOT NULL,
    notes text,
    published_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT plans_status_valid CHECK ((status = ANY (ARRAY['draft'::text, 'published'::text, 'replaced'::text])))
);


--
-- Name: questionnaire_answers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.questionnaire_answers (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    subscription_id uuid NOT NULL,
    question_id uuid NOT NULL,
    answer jsonb NOT NULL,
    photo_storage_key text,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: questionnaire_questions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.questionnaire_questions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    questionnaire_id uuid NOT NULL,
    "position" integer NOT NULL,
    type text NOT NULL,
    label text NOT NULL,
    options jsonb,
    required boolean DEFAULT true NOT NULL,
    is_archived boolean DEFAULT false NOT NULL
);


--
-- Name: questionnaires; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.questionnaires (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    coach_id uuid NOT NULL,
    title text NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: review_photos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.review_photos (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    review_id uuid NOT NULL,
    kind text NOT NULL,
    storage_key text NOT NULL,
    consent_given_at timestamp with time zone NOT NULL,
    status text DEFAULT 'pending'::text NOT NULL,
    CONSTRAINT review_photos_kind_valid CHECK ((kind = ANY (ARRAY['before'::text, 'after'::text]))),
    CONSTRAINT review_photos_status_valid CHECK ((status = ANY (ARRAY['pending'::text, 'visible'::text, 'rejected'::text, 'hidden'::text])))
);


--
-- Name: subscriptions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.subscriptions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    client_id uuid NOT NULL,
    coach_id uuid NOT NULL,
    package_id uuid NOT NULL,
    status text NOT NULL,
    price_piastres integer NOT NULL,
    commission_percent numeric(5,2) NOT NULL,
    commission_piastres integer NOT NULL,
    starts_at timestamp with time zone NOT NULL,
    ends_at timestamp with time zone NOT NULL,
    questionnaire_submitted_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: water_logs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.water_logs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    client_id uuid NOT NULL,
    log_date date NOT NULL,
    amount_ml integer NOT NULL,
    logged_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: weight_logs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.weight_logs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    client_id uuid NOT NULL,
    weight_kg numeric(5,1) NOT NULL,
    logged_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: client_addresses client_addresses_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.client_addresses
    ADD CONSTRAINT client_addresses_pkey PRIMARY KEY (id);


--
-- Name: client_health_profiles client_health_profiles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.client_health_profiles
    ADD CONSTRAINT client_health_profiles_pkey PRIMARY KEY (client_id);


--
-- Name: client_refresh_tokens client_refresh_tokens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.client_refresh_tokens
    ADD CONSTRAINT client_refresh_tokens_pkey PRIMARY KEY (id);


--
-- Name: client_refresh_tokens client_refresh_tokens_token_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.client_refresh_tokens
    ADD CONSTRAINT client_refresh_tokens_token_unique UNIQUE (token);


--
-- Name: clients clients_phone_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.clients
    ADD CONSTRAINT clients_phone_unique UNIQUE (phone);


--
-- Name: clients clients_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.clients
    ADD CONSTRAINT clients_pkey PRIMARY KEY (id);


--
-- Name: coach_documents coach_documents_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.coach_documents
    ADD CONSTRAINT coach_documents_pkey PRIMARY KEY (id);


--
-- Name: coach_packages coach_packages_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.coach_packages
    ADD CONSTRAINT coach_packages_pkey PRIMARY KEY (id);


--
-- Name: coach_refresh_tokens coach_refresh_tokens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.coach_refresh_tokens
    ADD CONSTRAINT coach_refresh_tokens_pkey PRIMARY KEY (id);


--
-- Name: coach_refresh_tokens coach_refresh_tokens_token_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.coach_refresh_tokens
    ADD CONSTRAINT coach_refresh_tokens_token_unique UNIQUE (token);


--
-- Name: coach_reviews coach_reviews_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.coach_reviews
    ADD CONSTRAINT coach_reviews_pkey PRIMARY KEY (id);


--
-- Name: coaches coaches_email_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.coaches
    ADD CONSTRAINT coaches_email_unique UNIQUE (email);


--
-- Name: coaches coaches_phone_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.coaches
    ADD CONSTRAINT coaches_phone_unique UNIQUE (phone);


--
-- Name: coaches coaches_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.coaches
    ADD CONSTRAINT coaches_pkey PRIMARY KEY (id);


--
-- Name: conversations conversations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.conversations
    ADD CONSTRAINT conversations_pkey PRIMARY KEY (id);


--
-- Name: conversations conversations_subscription_id_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.conversations
    ADD CONSTRAINT conversations_subscription_id_unique UNIQUE (subscription_id);


--
-- Name: messages messages_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.messages
    ADD CONSTRAINT messages_pkey PRIMARY KEY (id);


--
-- Name: notifications notifications_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_pkey PRIMARY KEY (id);


--
-- Name: payments payments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_pkey PRIMARY KEY (id);


--
-- Name: phone_verifications phone_verifications_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.phone_verifications
    ADD CONSTRAINT phone_verifications_pkey PRIMARY KEY (id);


--
-- Name: plan_meal_items plan_meal_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.plan_meal_items
    ADD CONSTRAINT plan_meal_items_pkey PRIMARY KEY (id);


--
-- Name: plan_meals plan_meals_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.plan_meals
    ADD CONSTRAINT plan_meals_pkey PRIMARY KEY (id);


--
-- Name: plans plans_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.plans
    ADD CONSTRAINT plans_pkey PRIMARY KEY (id);


--
-- Name: questionnaire_answers questionnaire_answers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.questionnaire_answers
    ADD CONSTRAINT questionnaire_answers_pkey PRIMARY KEY (id);


--
-- Name: questionnaire_questions questionnaire_questions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.questionnaire_questions
    ADD CONSTRAINT questionnaire_questions_pkey PRIMARY KEY (id);


--
-- Name: questionnaires questionnaires_coach_id_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.questionnaires
    ADD CONSTRAINT questionnaires_coach_id_unique UNIQUE (coach_id);


--
-- Name: questionnaires questionnaires_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.questionnaires
    ADD CONSTRAINT questionnaires_pkey PRIMARY KEY (id);


--
-- Name: review_photos review_photos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.review_photos
    ADD CONSTRAINT review_photos_pkey PRIMARY KEY (id);


--
-- Name: subscriptions subscriptions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subscriptions
    ADD CONSTRAINT subscriptions_pkey PRIMARY KEY (id);


--
-- Name: water_logs water_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.water_logs
    ADD CONSTRAINT water_logs_pkey PRIMARY KEY (id);


--
-- Name: weight_logs weight_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.weight_logs
    ADD CONSTRAINT weight_logs_pkey PRIMARY KEY (id);


--
-- Name: client_addresses_one_default_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX client_addresses_one_default_idx ON public.client_addresses USING btree (client_id) WHERE (is_default AND (deleted_at IS NULL));


--
-- Name: coach_documents_single_instance_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX coach_documents_single_instance_idx ON public.coach_documents USING btree (coach_id, type) WHERE (type <> 'certificate'::public.coach_document_type);


--
-- Name: coach_packages_coach_active_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX coach_packages_coach_active_idx ON public.coach_packages USING btree (coach_id, is_active);


--
-- Name: coach_reviews_coach_status_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX coach_reviews_coach_status_idx ON public.coach_reviews USING btree (coach_id, status);


--
-- Name: coach_reviews_subscription_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX coach_reviews_subscription_unique ON public.coach_reviews USING btree (subscription_id) WHERE ((subscription_id IS NOT NULL) AND (status <> 'rejected'::text));


--
-- Name: messages_conversation_client_ref; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX messages_conversation_client_ref ON public.messages USING btree (conversation_id, client_ref) WHERE (client_ref IS NOT NULL);


--
-- Name: messages_conversation_sent_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX messages_conversation_sent_idx ON public.messages USING btree (conversation_id, sent_at, id);


--
-- Name: notifications_recipient_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX notifications_recipient_idx ON public.notifications USING btree (recipient_type, recipient_id, created_at);


--
-- Name: payments_client_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX payments_client_idx ON public.payments USING btree (client_id);


--
-- Name: payments_subscription_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX payments_subscription_unique ON public.payments USING btree (subscription_id);


--
-- Name: phone_verifications_phone_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX phone_verifications_phone_idx ON public.phone_verifications USING btree (phone);


--
-- Name: plan_meals_plan_day_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX plan_meals_plan_day_idx ON public.plan_meals USING btree (plan_id, day_of_week);


--
-- Name: plans_one_published; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX plans_one_published ON public.plans USING btree (subscription_id) WHERE (status = 'published'::text);


--
-- Name: plans_subscription_version; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX plans_subscription_version ON public.plans USING btree (subscription_id, version);


--
-- Name: questionnaire_answers_one_per_question; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX questionnaire_answers_one_per_question ON public.questionnaire_answers USING btree (subscription_id, question_id);


--
-- Name: questionnaire_questions_order_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX questionnaire_questions_order_idx ON public.questionnaire_questions USING btree (questionnaire_id, "position");


--
-- Name: review_photos_review_kind_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX review_photos_review_kind_unique ON public.review_photos USING btree (review_id, kind);


--
-- Name: review_photos_review_status_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX review_photos_review_status_idx ON public.review_photos USING btree (review_id, status);


--
-- Name: subscriptions_client_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX subscriptions_client_idx ON public.subscriptions USING btree (client_id);


--
-- Name: subscriptions_coach_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX subscriptions_coach_idx ON public.subscriptions USING btree (coach_id);


--
-- Name: subscriptions_one_current; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX subscriptions_one_current ON public.subscriptions USING btree (client_id) WHERE (status <> ALL (ARRAY['ended'::text, 'cancelled'::text]));


--
-- Name: water_logs_client_day_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX water_logs_client_day_idx ON public.water_logs USING btree (client_id, log_date);


--
-- Name: weight_logs_client_time_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX weight_logs_client_time_idx ON public.weight_logs USING btree (client_id, logged_at);


--
-- Name: client_addresses client_addresses_client_id_clients_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.client_addresses
    ADD CONSTRAINT client_addresses_client_id_clients_id_fk FOREIGN KEY (client_id) REFERENCES public.clients(id) ON DELETE CASCADE;


--
-- Name: client_health_profiles client_health_profiles_client_id_clients_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.client_health_profiles
    ADD CONSTRAINT client_health_profiles_client_id_clients_id_fk FOREIGN KEY (client_id) REFERENCES public.clients(id) ON DELETE CASCADE;


--
-- Name: client_refresh_tokens client_refresh_tokens_client_id_clients_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.client_refresh_tokens
    ADD CONSTRAINT client_refresh_tokens_client_id_clients_id_fk FOREIGN KEY (client_id) REFERENCES public.clients(id) ON DELETE CASCADE;


--
-- Name: coach_documents coach_documents_coach_id_coaches_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.coach_documents
    ADD CONSTRAINT coach_documents_coach_id_coaches_id_fk FOREIGN KEY (coach_id) REFERENCES public.coaches(id) ON DELETE CASCADE;


--
-- Name: coach_packages coach_packages_coach_id_coaches_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.coach_packages
    ADD CONSTRAINT coach_packages_coach_id_coaches_id_fk FOREIGN KEY (coach_id) REFERENCES public.coaches(id) ON DELETE CASCADE;


--
-- Name: coach_refresh_tokens coach_refresh_tokens_coach_id_coaches_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.coach_refresh_tokens
    ADD CONSTRAINT coach_refresh_tokens_coach_id_coaches_id_fk FOREIGN KEY (coach_id) REFERENCES public.coaches(id) ON DELETE CASCADE;


--
-- Name: coach_reviews coach_reviews_client_id_clients_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.coach_reviews
    ADD CONSTRAINT coach_reviews_client_id_clients_id_fk FOREIGN KEY (client_id) REFERENCES public.clients(id);


--
-- Name: coach_reviews coach_reviews_coach_id_coaches_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.coach_reviews
    ADD CONSTRAINT coach_reviews_coach_id_coaches_id_fk FOREIGN KEY (coach_id) REFERENCES public.coaches(id) ON DELETE CASCADE;


--
-- Name: coach_reviews coach_reviews_subscription_id_subscriptions_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.coach_reviews
    ADD CONSTRAINT coach_reviews_subscription_id_subscriptions_id_fk FOREIGN KEY (subscription_id) REFERENCES public.subscriptions(id) ON DELETE SET NULL;


--
-- Name: conversations conversations_subscription_id_subscriptions_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.conversations
    ADD CONSTRAINT conversations_subscription_id_subscriptions_id_fk FOREIGN KEY (subscription_id) REFERENCES public.subscriptions(id) ON DELETE CASCADE;


--
-- Name: messages messages_conversation_id_conversations_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.messages
    ADD CONSTRAINT messages_conversation_id_conversations_id_fk FOREIGN KEY (conversation_id) REFERENCES public.conversations(id) ON DELETE CASCADE;


--
-- Name: payments payments_client_id_clients_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_client_id_clients_id_fk FOREIGN KEY (client_id) REFERENCES public.clients(id) ON DELETE CASCADE;


--
-- Name: payments payments_subscription_id_subscriptions_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_subscription_id_subscriptions_id_fk FOREIGN KEY (subscription_id) REFERENCES public.subscriptions(id) ON DELETE CASCADE;


--
-- Name: plan_meal_items plan_meal_items_plan_meal_id_plan_meals_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.plan_meal_items
    ADD CONSTRAINT plan_meal_items_plan_meal_id_plan_meals_id_fk FOREIGN KEY (plan_meal_id) REFERENCES public.plan_meals(id) ON DELETE CASCADE;


--
-- Name: plan_meals plan_meals_plan_id_plans_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.plan_meals
    ADD CONSTRAINT plan_meals_plan_id_plans_id_fk FOREIGN KEY (plan_id) REFERENCES public.plans(id) ON DELETE CASCADE;


--
-- Name: plans plans_subscription_id_subscriptions_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.plans
    ADD CONSTRAINT plans_subscription_id_subscriptions_id_fk FOREIGN KEY (subscription_id) REFERENCES public.subscriptions(id) ON DELETE CASCADE;


--
-- Name: questionnaire_answers questionnaire_answers_question_id_questionnaire_questions_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.questionnaire_answers
    ADD CONSTRAINT questionnaire_answers_question_id_questionnaire_questions_id_fk FOREIGN KEY (question_id) REFERENCES public.questionnaire_questions(id) ON DELETE RESTRICT;


--
-- Name: questionnaire_answers questionnaire_answers_subscription_id_subscriptions_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.questionnaire_answers
    ADD CONSTRAINT questionnaire_answers_subscription_id_subscriptions_id_fk FOREIGN KEY (subscription_id) REFERENCES public.subscriptions(id) ON DELETE CASCADE;


--
-- Name: questionnaire_questions questionnaire_questions_questionnaire_id_questionnaires_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.questionnaire_questions
    ADD CONSTRAINT questionnaire_questions_questionnaire_id_questionnaires_id_fk FOREIGN KEY (questionnaire_id) REFERENCES public.questionnaires(id) ON DELETE CASCADE;


--
-- Name: questionnaires questionnaires_coach_id_coaches_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.questionnaires
    ADD CONSTRAINT questionnaires_coach_id_coaches_id_fk FOREIGN KEY (coach_id) REFERENCES public.coaches(id) ON DELETE CASCADE;


--
-- Name: review_photos review_photos_review_id_coach_reviews_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.review_photos
    ADD CONSTRAINT review_photos_review_id_coach_reviews_id_fk FOREIGN KEY (review_id) REFERENCES public.coach_reviews(id) ON DELETE CASCADE;


--
-- Name: subscriptions subscriptions_client_id_clients_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subscriptions
    ADD CONSTRAINT subscriptions_client_id_clients_id_fk FOREIGN KEY (client_id) REFERENCES public.clients(id) ON DELETE CASCADE;


--
-- Name: subscriptions subscriptions_coach_id_coaches_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subscriptions
    ADD CONSTRAINT subscriptions_coach_id_coaches_id_fk FOREIGN KEY (coach_id) REFERENCES public.coaches(id);


--
-- Name: subscriptions subscriptions_package_id_coach_packages_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subscriptions
    ADD CONSTRAINT subscriptions_package_id_coach_packages_id_fk FOREIGN KEY (package_id) REFERENCES public.coach_packages(id);


--
-- Name: water_logs water_logs_client_id_clients_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.water_logs
    ADD CONSTRAINT water_logs_client_id_clients_id_fk FOREIGN KEY (client_id) REFERENCES public.clients(id) ON DELETE CASCADE;


--
-- Name: weight_logs weight_logs_client_id_clients_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.weight_logs
    ADD CONSTRAINT weight_logs_client_id_clients_id_fk FOREIGN KEY (client_id) REFERENCES public.clients(id) ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

\unrestrict coachnarails

