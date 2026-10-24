# Otimizador de Performance para Windows 10/11

Script em **PowerShell** com menu interativo para otimizar e manter o Windows 10 e 11. Cada alteração é registada e **pode ser revertida**.

> ⚠️ **Leia antes de usar.** Este script altera configurações do sistema (registro, serviços, tarefas agendadas, rede e energia). Os ajustes usados são documentados e reversíveis, mas **o projeto não é certificado nem auditado por terceiros** e o ganho de desempenho depende do hardware. Leia o código, teste primeiro numa máquina virtual ou num PC não crítico e mantenha cópias de segurança dos seus dados.

---

## Índice

- [O que é](#o-que-é)
- [O que NÃO é](#o-que-não-é)
- [Funcionalidades](#funcionalidades)
- [Requisitos](#requisitos)
- [Como usar](#como-usar)
- [Segurança e reversão](#segurança-e-reversão)
- [Classificação de risco](#classificação-de-risco)
- [Limitações conhecidas](#limitações-conhecidas)
- [Estrutura do projeto](#estrutura-do-projeto)
- [Contribuir](#contribuir)
- [Licença e aviso legal](#licença-e-aviso-legal)

---

## O que é

Uma ferramenta de linha de comandos com interface em modo texto que agrupa, em 12 áreas, ajustes e rotinas de manutenção conhecidos do Windows. Foi desenhada com três princípios:

1. **Transparência:** cada opção diz o que faz, e o modo simulação mostra o código que seria executado sem alterar nada.
2. **Reversibilidade:** antes de alterar um valor de registro, serviço ou tarefa, o script guarda o valor original.
3. **Prudência:** não mexe em serviços críticos e evita "truques" sem base técnica.

## O que NÃO é

- Não é um "acelerador mágico". Em PCs já bem configurados, os ganhos são pequenos.
- Não limpa a memória RAM por script, não altera a reserva de banda QoS e não desativa Windows Update, Defender ou Firewall. Estes são mitos de otimização ou riscos de segurança.
- Não é um antivírus nem substitui backups.
- Não faz overclock nem altera a BIOS/UEFI.

## Funcionalidades

| # | Área | Exemplos do que inclui |
|---|------|------------------------|
| 1 | Inicialização e desligamento | Reduzir tempos de encerramento, remover atraso de inicialização, Fast Startup, listar programas de arranque, tempo do último boot |
| 2 | Acesso (disco e arquivos) | Último acesso NTFS, verificar/ativar TRIM, caminhos longos, Explorador abre em "Este Computador" |
| 3 | Controle energético | Planos de energia (inclui Desempenho Máximo), suspensão seletiva USB, hibernação, relatório de bateria |
| 4 | Memória e processamento | Uso de memória, top processos, apps em segundo plano, pagefile gerido pelo Windows, compressão de memória, SysMain |
| 5 | Drives e periféricos | Saúde dos discos, TRIM em SSD e desfragmentação em HDD, dispositivos com erro, rato sem aceleração, teclado mais rápido |
| 6 | Rede e internet | Diagnóstico, cache DNS, ajuste TCP, DNS Cloudflare/Google/automático, energia dos adaptadores, Otimização de Entrega, reset de rede |
| 7 | Jogos | Modo de Jogo, desativar Game DVR, HAGS, prioridade MMCSS, cache de shaders, perfil Gamer num passo |
| 8 | Serviços e telemetria | Telemetria, serviços e tarefas associados, publicidade e sugestões, lista de serviços desnecessários |
| 9 | Gráfica | Efeitos visuais, ClearType, informação da GPU, HAGS, cache de shaders |
| 10 | Interface e usabilidade | Extensões e itens ocultos, atraso dos menus, pesquisa web no Iniciar, Teclas de Aderência, menu de contexto clássico e barra de tarefas (Windows 11) |
| 11 | Controle de manutenção | Limpeza de temporários, DISM + SFC, CHKDSK online, limpeza do WinSxS, ponto de restauração, espaço em disco |
| 12 | Expansão de manutenção | Limpeza semanal agendada, Sensor de Armazenamento, Manutenção Automática, `winget upgrade`, relatórios de energia e do sistema |

Outras funções do programa:

- **Verificação de privilégios:** se não estiver em modo administrador, pede elevação (UAC) automaticamente.
- **Deteção de hardware:** identifica portátil ou desktop e SSD ou HDD, e ajusta avisos e bloqueios em função disso.
- **Verificação de perfil de utilizador:** avisa se os ajustes de utilizador (HKCU) iriam para uma conta diferente da sessão ativa.
- **Modo simulação** (tecla `S`): mostra o que seria feito, sem alterar o sistema.
- **Registo de atividade** em `%ProgramData%\OtimizadorWindows\otimizador.log`.

## Requisitos

- Windows 10 (build 10240 ou superior) ou Windows 11
- PowerShell 5.1 (já incluído no Windows)
- Conta com direitos de administrador

## Como usar

1. Descarregue os ficheiros deste repositório para uma pasta (por exemplo, `C:\Otimizador`).
2. Clique com o botão direito em `Iniciar.bat` e escolha *Executar como administrador* (ou dê duplo clique e aceite o pedido do UAC).
3. Responda se quer criar um **ponto de restauração** (recomendado).
4. Escolha uma área pelo número e depois a opção desejada.

Alternativa, num PowerShell:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\OtimizadorWindows.ps1
```

> O `Iniciar.bat` usa `-ExecutionPolicy Bypass` apenas para esta execução e não altera a política do sistema.

### Atalhos do menu principal

| Tecla | Ação |
|-------|------|
| `1`–`12` | Abrir a área correspondente |
| `R` | Reverter todas as alterações feitas pelo programa |
| `P` | Criar ponto de restauração |
| `S` | Ligar/desligar o modo simulação |
| `0` | Sair |

## Segurança e reversão

- **Ponto de restauração:** o script levanta temporariamente o limite de um ponto por 24 horas para poder criar o seu, e depois repõe o valor original.
- **Backup automático:** os valores originais ficam em `%ProgramData%\OtimizadorWindows\backup.jsonl`. A opção `[R]` restaura-os (registro, tipo de arranque dos serviços, incluindo arranque atrasado, e tarefas agendadas).
- **Reinício:** algumas alterações só têm efeito após reiniciar. O programa avisa quando isso acontece.
- **O que não é revertido pela opção `[R]`:** ações que não são alterações de configuração, como arquivos apagados na limpeza, `netsh winsock reset`, DNS definido manualmente (use a opção "DNS automático") e planos de energia criados. Para tudo o resto, use o ponto de restauração.

## Classificação de risco

Cada opção dos submenus é etiquetada:

| Etiqueta | Significado |
|----------|-------------|
| 🟢 **Seguro** | Ajuste de baixo impacto e fácil de reverter |
| 🟡 **Moderado** | Pode alterar comportamento visível (autonomia, privacidade, rede) |
| 🔴 **Avançado** | Pode causar perda de funcionalidades se mal aplicado; leia antes de confirmar |

A classificação é uma orientação do autor e não substitui a avaliação de um profissional de T.I. no seu ambiente.

## Limitações conhecidas

- **Em desenvolvimento:** a versão 1.0 foi escrita sem testes automatizados. Relate qualquer problema nas *Issues*.
- Ainda não validado em todas as edições (Home, Pro, Enterprise, LTSC) nem em todos os idiomas do Windows.
- Algumas opções dependem do hardware, por exemplo o HAGS (exige GPU e driver compatíveis) e os planos de energia em dispositivos com *Modern Standby*.
- Em Windows Home e Pro, o nível mínimo de telemetria definido pelo Windows ("Necessário") não pode ser eliminado por política.
- O Windows 11 mais recente pode bloquear algumas alterações de interface (por exemplo, com proteção do utilizador contra alterações de associação de ficheiros).
- O modo simulação mostra o código que seria executado, não uma comparação do valor atual com o novo.
- Em ambientes geridos por empresa, políticas de grupo (GPO) podem anular as alterações.

## Estrutura do projeto

```
.
├── OtimizadorWindows.ps1   # Script principal (menu, funções e ajustes)
├── Iniciar.bat             # Lançador (executa o script com a política de execução necessária)
└── README.md
```

## Contribuir

Sugestões e correções são bem-vindas:

1. Abra uma *Issue* descrevendo o problema ou a proposta (indique a versão do Windows e a edição).
2. Para alterações de código, faça um *fork* e abra um *Pull Request*.
3. Novos ajustes devem ser **documentados** (fonte oficial ou técnica), **reversíveis** e passar pelo `Set-Reg`, `Set-Svc` ou `Disable-Tarefa`, para ficarem no backup.
4. Antes de propor, execute o **PSScriptAnalyzer** e teste numa máquina virtual.

## Licença e aviso legal

Defina a licença do projeto antes de publicar (por exemplo, MIT) e adicione o ficheiro `LICENSE`.

**Este software é fornecido "tal como está", sem garantias de qualquer tipo.** O autor não se responsabiliza por perda de dados, instabilidade do sistema ou qualquer outro dano resultante do uso. Use por sua conta e risco e sempre com cópias de segurança.

Windows, PowerShell e outras marcas citadas pertencem aos respetivos proprietários. Este projeto não é afiliado nem endossado pela Microsoft.
