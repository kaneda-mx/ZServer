# Guia: Habilitar APM/Tracing para vidaapi-ctza

Entorno Actual
- Cluster: oprosa (ROSA/OpenShift en AWS us-east-1)
- Namespace: sb-sales-channels-prd (PRD) / sb-sales-channels-pre (PRE)
- Deployment: vidaapi-ctza
- Lenguaje: Java
- Datadog Agent: Instalado (13 nodos, namespace datadog)
- Cluster Agent: Instalado (2 replicas, namespace datadog)

## Responsables de lado de SB

- Lidia

## Paso 1: Verificar Admission Controller
Revisar configuracion del Cluster Agent:

kubectl get configmap datadog-agent-cluster-agent -n datadog -o yaml | grep -A5 admission

Debe mostrar 
admission_controller.enabled:
true

## Paso 2: Agregar Labels y Annotations al Deployment
```
apiVersion: apps/v1
kind: Deployment
metadata:
  name: vidaapi-ctza
  namespace: sb-sales-channels-prd
spec:
  template:
    metadata:
      labels:
        admission.datadoghq.com/enabled: "true"
        tags.datadoghq.com/env: "prd"
        tags.datadoghq.com/service: "vidaapi-ctza"
        tags.datadoghq.com/version: "1.0"
      annotations:
        admission.datadoghq.com/java-lib.version: "v1.12.0"
```
## Paso 3: Aplicar y reiniciar
```
kubectl apply -f deployment-vidaapi-ctza.yaml
kubectl rollout restart deployment/vidaapi-ctza -n sb-sales-channels-prd
```
## Paso 4: Verificar inyeccion
```
kubectl describe pod -l app=vidaapi-ctza -n sb-sales-channels-prd
```
Buscar:
```
Init container: datadog-lib-java-init
Variable: 
JAVA_TOOL_OPTIONS: -javaagent:/datadog-lib/dd-java-agent.jar
JAVA_TOOL_OPTIONS:
-javaagent:/datadog-lib/dd-java-agent.jar
Alternativa Manual (si no hay Admission Controller)
ADD 'https://dtdg.co/latest-java-tracer' /opt/dd-java-agent.jar

env:
  - name: JAVA_TOOL_OPTIONS
    value: "-javaagent:/opt/dd-java-agent.jar"
  - name: DD_SERVICE
    value: "vidaapi-ctza"
  - name: DD_ENV
    value: "prd"
  - name: DD_VERSION
    value: "1.0"
  - name: DD_AGENT_HOST
    valueFrom:
      fieldRef:
        fieldPath: status.hostIP
```
## Recomendacion
Probar primero en PRE (sb-sales-channels-pre) antes de aplicar en PRD.

## Documentacion
https://docs.datadoghq.com/tracing/guide/tutorial-enable-java-admission-controller/
https://docs.datadoghq.com/tracing/guide/local_sdk_injection/
Puedes seleccionar todo el texto de arriba y copiarlo. Si necesitas algo mas, aqui estoy.