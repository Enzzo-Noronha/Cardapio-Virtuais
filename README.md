# Cardápio Online 🍕

Um cardápio digital simples, rápido e responsivo, pensado para qualquer restaurante, pizzaria, lanchonete ou bar que queira receber pedidos direto pelo WhatsApp — sem taxas de marketplace, sem backend obrigatório e sem complicação.

Feito para ser **clonado e personalizado**: troque as cores, os itens do cardápio e o número de WhatsApp, e em poucos minutos você tem seu próprio cardápio no ar.

## ✨ Funcionalidades

- **Cardápio por categorias**, organizado em abas (ex: Lanches, Pizzas, Bebidas) e subseções dentro de cada aba.
- **Itens com tamanhos/variações**: um mesmo prato pode ter vários preços (P/M/G/GG, Dose/Litro, Copo/Jarra etc.) — cada variação vira um botão próprio de "adicionar".
- **Carrinho de compras** com:
  - visual compacto por item (nome, quantidade, preço em uma linha só), pra não ocupar espaço quando há muitos pedidos;
  - botões de aumentar/diminuir quantidade;
  - observação por item, escondida por padrão e expansível sob demanda;
  - cupom de desconto (percentual, validado em JavaScript);
  - subtotal, taxa de entrega e total recalculados automaticamente.
- **Finalização do pedido**: nome, endereço, forma de pagamento (Dinheiro, Cartão ou Pix) e observação geral.
  - Ao escolher **Pix**, a chave aparece na tela com botão de copiar.
  - Ao escolher **Dinheiro**, aparece um campo opcional de troco.
- **Envio direto para o WhatsApp**: ao confirmar, o sistema monta uma mensagem formatada com todos os itens, valores, dados do cliente e pagamento, e abre o WhatsApp já com tudo preenchido — o cliente só aperta enviar.

## 🧱 Stack

HTML, CSS e JavaScript puros — sem frameworks, sem build step, sem dependências. Basta abrir o `.html` no navegador ou hospedar em qualquer servidor estático.

## 🎨 Como personalizar as cores

As cores ficam centralizadas em variáveis CSS no topo do arquivo, dentro de `:root`:

```css
:root{
    --bg: #15110b;        /* fundo geral da página */
    --card: #ece1c7;      /* fundo dos cartões de produto */
    --card-border: #c9a227;
    --gold: #c9a227;       /* cor de destaque (botões, títulos de seção) */
    --gold-dark: #a9821c;
    --text: #241f18;
    --text-muted: #6b5f4a;
    --danger: #b23b2e;    /* cor do botão de remover */
}
```

Troque esses valores pela paleta da sua marca — o resto do layout se adapta automaticamente.

## 🛠️ Como personalizar o cardápio

Os itens ficam em arrays de JavaScript, um por categoria, logo no começo da tag `<script>`. Cada item é criado com uma função auxiliar, dependendo do tipo de preço:

| Função | Uso | Exemplo |
|---|---|---|
| `un(nome, desc, valor)` | Preço único | `un("Misto Quente", "Presunto e queijo.", 10)` |
| `pz(nome, desc, tag, p, m, g, gg)` | 4 tamanhos (pizza/calzone) | `pz("Calabresa", "...", "Tradicional", 28, 33, 38, 55)` |
| `ps(nome, desc, v300, v500)` | Porções (300g/500g) | `ps("Batata Frita", "", 20, 25)` |
| `jr(nome, desc, copo, jarraP, jarraG)` | Sucos | `jr("Maracujá", "", 7, 15, 20)` |
| `dl(nome, desc, dose, litro)` | Bebidas destiladas | `dl("Red Label", "", 10, 170)` |

Para adicionar, editar ou remover um produto, basta mexer nessas listas — o cardápio inteiro é renderizado dinamicamente a partir delas, então não é preciso tocar em HTML.

Para criar uma categoria/aba nova:
1. Adicione um novo `<button class="tab" data-target="minha-secao">` na `<nav>`.
2. Adicione a `<section id="minha-secao" class="cardapio-secao"></section>` correspondente em `<main>`.
3. Crie o array de dados da categoria e chame `renderSecao("minha-secao", MEU_ARRAY)` junto com as demais chamadas de renderização.

## ⚙️ Configurações rápidas

No topo do `<script>`:

```js
const TAXA_ENTREGA = 5.00;                     // valor fixo da taxa de entrega
const WHATSAPP_NUMERO = "55DDNUMERO";          // número que recebe os pedidos
const CHAVE_PIX = "sua-chave-pix";             // chave exibida quando o cliente escolhe Pix
```

O cupom de desconto de exemplo fica na função `aplicarCupom()` — troque o código e o percentual, ou adapte para validar contra uma lista de cupons.

## 🚀 Como rodar

Não precisa de servidor nem instalação:

1. Baixe o arquivo `.html`.
2. Abra direto no navegador, ou
3. Hospede em qualquer serviço de arquivos estáticos (GitHub Pages, Netlify, Vercel, cPanel etc.).

## 🗺️ Roadmap (ideias para evoluir)

Coisas que ficam de fora do MVP de propósito, mas são bons próximos passos para quem for construir em cima disso:

- Painel administrativo para cadastrar produtos sem editar código
- Upload de imagens dos produtos
- Cadastro de cupons com banco de dados
- Controle de disponibilidade e horário de funcionamento
- QR Code para mesas
- Histórico de pedidos e estatísticas

## 📄 Licença

Sinta-se livre para clonar, adaptar e usar este cardápio no seu próprio negócio ou nos negócios dos seus clientes.