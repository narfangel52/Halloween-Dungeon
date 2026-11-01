# Nerfangel • Torre Simples 1.0

Versão independente, sem chave nem biblioteca externa de interface. O hub completo continua separado e não foi alterado.

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/narfangel52/Halloween-Dungeon/main/PolyLoot_Torre_Simples.lua"))()
```

1. Pare qualquer farm do hub completo/outros scripts.
2. Entre manualmente na Infinite Tower e equipe a arma que deseja usar.
3. Execute o carregador e clique em INICIAR FARM.

Mantém posição acima do alvo, mira para baixo, ativa somente a arma equipada e reconhece os monstros vivos da arena atual. Não depende de lista fixa de espécies: funciona também com os monstros da Beach quando aparecem na torre. Usa atributos de run quando disponíveis para excluir outras partidas. Permanece no alvo vivo e troca após morte/remoção. Altura padrão 10, ajuste 4–20 pelos botões −/+. Teleporte confirmado após 0,25 s, suspensão no ar e colisões locais temporariamente desligadas. Se ficar sem observar dano por 8 s, alterna pequeno deslocamento lateral à mesma altura; não mergulha no inimigo.

Avança apenas nos botões confirmados NEXT FLOOR e READY de TowerRunV5. Uma tentativa por run/andar/tela; ausência de monstros não significa vitória. Se um clique não responder, use o botão do próprio jogo ou desligue/ligue Avançar/READY para liberar outra tentativa. Para ao morrer, ser derrotado ou sair da torre. Fechar/parar restaura os valores originais de colisão, AutoRotate e PlatformStand. Copiar diagnóstico registra estado, arma, alvo, posição e últimos 60 eventos.

Sem troca de armas, venda, coleta, entrada automática, repetição após derrota ou compras de revive. Equipar uma arma é responsabilidade do jogador. A altura pode reduzir a exposição a ataques de contato, mas não garante imunidade a ataques do servidor ou em área. Aumentar a altura também pode tirar a arma de alcance.

Validação: sintaxe Luau completa e execução simulada das funções reais em audit/test_tower_simple.py (lupa; usa os fixtures de test_tower324.py). Casos: entrada manual, arma preservada, arena/run/NPC vivo, retenção de alvo; teleporte, orientação, rejeição de chegada e cooldown; cancelamento, restauração de Humanoid/colisões, partes novas/removidas; cliques únicos, waves vazias, waves dinâmicas, derrota; Enabled/cooldown da arma e ajuste lateral sem descer. Verificação estática confirma ausência de equip/troca de arma, dependência externa, pedido de RemoteEvent, coleta ou chave. Arquivos publicados lidos novamente e comparados. Não houve teste dentro do Roblox/executor.
