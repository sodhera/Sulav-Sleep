-- Reviewed iOS builds understand exactly two copy and scene variants.
-- Editing these values is an OTA configuration change, not executable code.
alter table public.app_config
  add column if not exists onboarding_copy_variant text not null default 'concise',
  add column if not exists onboarding_scene_variant text not null default 'twilight';

alter table public.app_config
  add constraint app_config_onboarding_copy_valid
    check (onboarding_copy_variant in ('concise', 'classic')),
  add constraint app_config_onboarding_scene_valid
    check (onboarding_scene_variant in ('twilight', 'classic'));
