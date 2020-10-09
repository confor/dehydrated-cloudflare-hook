## dehydrated-cloudflare-hook
un script para [dehydrated](https://github.com/dehydrated-io/dehydrated), para usar con `dns-01` y cloudflare.

dehydrated es un cliente para pedir certificados a letsencrypt y el reto `dns-01` permite obtener certificados sin tener un servidor http.

este script cambia automáticamente el dns de cloudflare.

### cómo usar
copiar `config-example.sh` a `config.sh` y modificar:

debe quedar algo así:

    global_api_key="abcdef12345678abcdef1234abcdefabcdefa"
    zone_id="23456781234abcdefabcdef123412341"
    email="admin@example.org"

es posible soportar varios dominios en la misma configuración, igual que en [cfhookbash](https://github.com/sineverba/cfhookbash/blob/4.0.0/config.default.sh):

    case "${DOMAIN}" in
        "www.example.com")
            global_api_key="abcdef12345678abcdef1234abcdefabcdefa"
            zone_id="23456781234abcdefabcdef123412341"
            email="aaaaaa@example.com"
        ;;

        "www.example.net")
            global_api_key="abcdefabcdefabcdef12341234abcdef12345"
            zone_id="23456781234abcdefabcdef123412341"
            email="bbbbbbb@example.net"
        ;;
    esac

finalmente, agregar el hook a dehydrated:

    HOOK=dehydrated-cloudflare-hook/hook.sh

### nota
el script escribe archivos temporales para guardar el resultado de la api de cloudflare. es necesario que dehydrated tenga permisos de escritura en la carpeta de `hook.sh`.

### referencias
- [dehydrated/docs/examples/hook.sh](https://github.com/dehydrated-io/dehydrated/blob/master/docs/examples/hook.sh)
- [sineverba/cfhookbash](https://github.com/sineverba/cfhookbash), que me inspiró a hacer este script
- [api.cloudflare.com](https://api.cloudflare.com/#dns-records-for-a-zone-create-dns-record)
