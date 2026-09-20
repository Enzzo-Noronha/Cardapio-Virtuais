-- Execute este arquivo SOMENTE depois de criar o usuário no painel do Supabase:
-- Authentication > Users > Add user
-- E-mail técnico: thaisa@login.imperiodoacai.com
-- Marque "Auto Confirm User".
--
-- A tela de administração não exibirá esse e-mail.
-- A proprietária entrará apenas com: Thaisa
-- Defina a senha solicitada no painel do Supabase, não neste arquivo.

insert into public.store_admins (business_id, user_id)
select b.id, u.id
from public.businesses b
join auth.users u on u.email = 'thaisa@login.imperiodoacai.com'
where b.slug = 'thaisa-acai'
on conflict (business_id, user_id) do nothing;

-- Verificação: deve retornar uma linha.
select b.name as loja, u.email as email_tecnico, u.id as usuario_id
from public.store_admins sa
join public.businesses b on b.id = sa.business_id
join auth.users u on u.id = sa.user_id
where b.slug = 'thaisa-acai';
