-- Execute APÓS criar a loja com o slug 'thaisa-acai'.
-- É seguro executar uma vez em um banco novo.
do $$
declare
  v_business uuid;
  v_acai uuid;
  v_especiais uuid;
  v_picoles uuid;
begin
  select id into v_business from public.businesses where slug = 'thaisa-acai';
  if v_business is null then
    raise exception 'Crie primeiro a loja com o slug thaisa-acai.';
  end if;

  insert into public.categories (business_id, name, position, active)
  values (v_business, 'Açaí por peso', 1, true), (v_business, 'Combinações especiais', 2, true),
         (v_business, 'Picolés', 3, true), (v_business, 'Sorvetes', 4, false);

  select id into v_acai from public.categories where business_id=v_business and name='Açaí por peso' limit 1;
  select id into v_especiais from public.categories where business_id=v_business and name='Combinações especiais' limit 1;
  select id into v_picoles from public.categories where business_id=v_business and name='Picolés' limit 1;

  insert into public.products (business_id,category_id,name,description,price,included_complements,includes_coverage) values
  (v_business,v_acai,'Açaí 130 g','Inclui 2 complementos + cobertura.',10,2,true),
  (v_business,v_acai,'Açaí 200 g','Inclui 3 complementos + cobertura.',15,3,true),
  (v_business,v_acai,'Açaí 265 g','Inclui 4 complementos + cobertura.',20,4,true),
  (v_business,v_acai,'Açaí 330 g','Inclui 4 complementos + cobertura.',25,4,true),
  (v_business,v_acai,'Açaí 400 g','Inclui 5 complementos + cobertura.',30,5,true),
  (v_business,v_acai,'Açaí 465 g','Inclui 5 complementos + cobertura.',35,5,true),
  (v_business,v_acai,'Açaí 530 g','Inclui 6 complementos + cobertura.',40,6,true),
  (v_business,v_acai,'Açaí 600 g','Inclui 6 complementos + cobertura.',45,6,true),
  (v_business,v_especiais,'Açaí Kids','Marshmallow, M&M, Chocoboll e cobertura de chocolate. Tamanho P.',15,0,true),
  (v_business,v_especiais,'Açaí Festa','Jujuba, Fini, canudinho, granulado e cobertura de morango.',25,0,true),
  (v_business,v_especiais,'Açaí Choconmania','Bis, gotas de chocolate, Chocoboll, creme chocolatudo e cobertura de chocolate. Tamanho M.',25,0,true),
  (v_business,v_especiais,'Açaí Paçoquita','Paçoca, banana, leite em pó, creme de leitinho e leite condensado. Tamanho G.',35,0,true),
  (v_business,v_especiais,'Açaí Delícia de Morango','Morango, creme de leitinho, granulado e cobertura de morango.',25,0,true),
  (v_business,v_picoles,'Picolé – sabores variados','Unidade.',2,0,false);

  insert into public.complements (business_id,name,price,kind) values
  (v_business,'Bis',2,'complemento'),(v_business,'Pedaços de castanha',2,'complemento'),
  (v_business,'Pedaços de casquinha',2,'complemento'),(v_business,'Creme de leitinho',2,'complemento'),
  (v_business,'Creme chocolatudo',2,'complemento'),(v_business,'Creme de maracujá',2,'complemento'),
  (v_business,'Coco ralado',2,'complemento'),(v_business,'Gotas de chocolate',2,'complemento'),
  (v_business,'Granulado',2,'complemento'),(v_business,'Jujuba',2,'complemento'),
  (v_business,'Canudinho',2,'complemento'),(v_business,'Banana',2,'complemento'),
  (v_business,'Morango',2,'complemento'),(v_business,'M&M',2,'complemento'),
  (v_business,'Paçoca',2,'complemento'),(v_business,'Cereja',2,'complemento'),
  (v_business,'Brigadeiro',2,'complemento'),(v_business,'Leite em pó',2,'complemento'),
  (v_business,'Chocoboll',2,'complemento'),(v_business,'Marshmallow',2,'complemento'),
  (v_business,'Fini',2,'complemento'),
  (v_business,'Chocolate',0,'cobertura'),(v_business,'Morango',0,'cobertura'),
  (v_business,'Doce de leite',0,'cobertura'),(v_business,'Leite condensado',0,'cobertura');

  insert into public.localities (business_id,name,fee) values
  (v_business,'Campestre',1),(v_business,'Agrovila',1),(v_business,'Lagoa de Dentro',1),
  (v_business,'Acampamento',1),(v_business,'Caraúbas',1),(v_business,'Henriques 2',1),
  (v_business,'Inhamuns',1),(v_business,'Monte Alegre (próximo à casa do Atagnam)',1),
  (v_business,'Xique-Xique',1),(v_business,'Chapadinha',1),
  (v_business,'Açude do Sales (próximo à casa da Valcira)',1);

  insert into public.payment_methods (business_id,method,active) values
  (v_business,'pix',true),(v_business,'cash',true)
  on conflict (business_id,method) do update set active=excluded.active;

  update public.businesses set name='Império do Açaí', contact='Açaí e sorvete',
    whatsapp='5588996227352', pix_key='996227352 — Maria Thaisa Costa Araújo',
    opening_hours='Entrega em 30 a 90 minutos, conforme distância e demanda.'
  where id=v_business;
end $$;
