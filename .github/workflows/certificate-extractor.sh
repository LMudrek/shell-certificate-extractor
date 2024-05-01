name: Atualiza Certificados

on:
  workflow_dispatch:
    inputs:
      certificate_url:
        description: 'URL a ser extraída certificado'
        default: 'api.github.com'
        required: true
        type: string
      cert_path:
        description: 'Caminho e nome a ser salvo certificado'
        default: 'app/certs/github-chain.cer'
        required: true
        type: string

jobs:
  extrai-certificado:
    runs-on: itau-linux

    - name: Extrai certificado e cadeia
      id: cert_extract
      run: |

        saveexpirationdate() {
          json='{"timestampValidade":%d,"timestampEmissao":%d}'
          path="$(dirname "$2")/certificate-info.json"

          cert_not_after=$(date --date="$(openssl x509 -noout -startdate -in $1 | awk -F '=' '{print $NF}' )" +"%s")
          cert_not_before=$(date --date="$(openssl x509 -noout -enddate -in $1 | awk -F '=' '{print $NF}' )" +"%s")
          printf "$json" $cert_not_before $cert_not_after > $path
        }

        # from https://stackoverflow.com/a/68637388/5401366
        getcaissuer() {
          openssl x509 -noout -text -in $1 -extensions authorityInfoAccess | awk '/^[ \t]+CA Issuers[ \t]+-[ \t]+URI:/ { print gensub(/^.*URI:(.*)$/,"\\1","g",$0); }'
        }

        # Recupera URL do job anterior
        CERT_PATH=${{ inputs.cert_path}}
        URL_CERTIFICADO=${{ inputs.certificate_url }}

        machine_cert=${URL_CERTIFICADO}.pem.temp

        if [ ! -e "${machine_cert}" ];
        then
          openssl s_client -host $URL_CERTIFICADO -port 443 -showcerts -servername $URL_CERTIFICADO -tls1_2 </dev/null 2>/dev/null | openssl x509 -outform PEM > ${machine_cert}
        fi;

        cur_cert=$machine_cert
        cat $machine_cert > $CERT_PATH

        # Salva JSON com data de validade certificado
        saveexpirationdate $cur_cert $CERT_PATH

        while :;
        do
            echo "Current Cert: ${cur_cert}"

            # Get the first matching http line to grab the next cert loc
            nextca=$(getcaissuer ${cur_cert})

            echo "Next CA: ${nextca}"

            # ran out of stuff to retrieve
            if [ -z "${nextca}" ]; then
              echo "End of script"
              break
            fi

            nextca=$(echo $nextca | grep -m1 http)

            echo "Trying to get '${nextca}'"

            nextfile=$(basename ${nextca})

            if [ ! -e ${nextfile} ];
            then
                echo "Getting $nextca"
                curl -sO $nextca -v
            else
                echo "Found ${nextfile}"
            fi

            # Convert
            cat $nextfile | openssl x509 -inform DER -outform PEM > ${nextfile}.temp
            cat $nextfile | openssl x509 -inform DER -outform PEM >> $CERT_PATH
            rm $nextfile

            # down the rabbit hole...
            cur_cert=${nextfile}.temp
        done

        echo "Removendo arquivos .temp"

        rm *.temp

    - name: Extraction Status
      if: always()
      run: |
        if [ "${{ steps.cert_extract.outcome }}" != "success" ]; then
          echo "### Ocorreu um erro na extração do certificado :rotating_light:" >> $GITHUB_STEP_SUMMARY
          echo "Valide a execução da action" >> $GITHUB_STEP_SUMMARY
          echo "- - -" >> $GITHUB_STEP_SUMMARY
        fi
        if [[ "${{ steps.cert_extract.outcome }}" = "success" && "${{ steps.git_commit.outcome }}" = "success" ]]; then
          echo "### A extração foi realizada com sucesso! :white_check_mark:" >> $GITHUB_STEP_SUMMARY
          echo "A esteira irá realizar o build e disponibilizar um Pull Request (PR) automaticamente." >> $GITHUB_STEP_SUMMARY
          echo " " >> $GITHUB_STEP_SUMMARY
          echo "- - -" >> $GITHUB_STEP_SUMMARY
        fi
        if [[ "${{ steps.cert_extract.outcome }}" = "success" && "${{ steps.git_commit.outcome }}" != "success" ]]; then
          echo "### Ocorreu um erro no commit para o repositório desejado :rotating_light:" >> $GITHUB_STEP_SUMMARY
          echo "Para corrigir verifique se o certificado já está renovado na URL ${{ inputs.certificate_url }}" >> $GITHUB_STEP_SUMMARY
          echo "- - -" >> $GITHUB_STEP_SUMMARY
        fi

        echo "Se tiver dúvidas sobre a utilização, entre em contato com a [Governança de Canais](https://curly-adventure-p1o2vpr.pages.github.io/ajuda/)." >> $GITHUB_STEP_SUMMARY