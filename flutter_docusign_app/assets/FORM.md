# Padrões do PDF (importante):

1. Abra o PDF que deseja mapear usando o LibreOffice.

2. Insira os campos de texto e checkboxes interativas onde deseja.

3. Edite os nomes dos campos de texto e checkboxes de acordo com o que o usuário vai preencher, esse nome é o que vai aparecer na lista de inputs. Caso exista espaços duplicados (tipo a data por exemplo), deixe o nome desses campos iguais.

4. Para o desenho da assinatura, adicione um campo de texto interativo, e insira o nome padrão a seguir:

assinatura_cliente.<número da página> - exemplo: assinatura_cliente.1

*AVISO*: Caso exista múltiplos espaços onde a assinatura será inserida, o tamanho das caixas de texto das assinaturas devem ser *idênticas* (ctrl c + ctrl v).

5. Exporte o PDF como PDF 2.0 com as seguintes configurações:

"Criar Formulário PDF"
"Formato para envio: PDF"
"Permitir nomes de campos duplicados"

# Insira o pdf desejado neste diretório com o nome:

sample_form.pdf
