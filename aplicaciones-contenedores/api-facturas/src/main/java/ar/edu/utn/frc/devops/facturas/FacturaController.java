package ar.edu.utn.frc.devops.facturas;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

@RestController
@RequestMapping("/facturas")
public class FacturaController {

    private final FacturaRepository repository;

    public FacturaController(FacturaRepository repository) {
        this.repository = repository;
    }

    // GET /facturas -> listar todas
    @GetMapping
    public List<Factura> listar() {
        return repository.findAll();
    }

    // GET /facturas/{id} -> obtener una
    @GetMapping("/{id}")
    public ResponseEntity<Factura> obtener(@PathVariable Long id) {
        return repository.findById(id)
                .map(ResponseEntity::ok)
                .orElseGet(() -> ResponseEntity.notFound().build());
    }

    // POST /facturas -> crear (alta)
    @PostMapping
    public ResponseEntity<Factura> crear(@RequestBody Factura factura) {
        factura.setId(null);
        Factura creada = repository.save(factura);
        return ResponseEntity.status(HttpStatus.CREATED).body(creada);
    }

    // PUT /facturas/{id} -> modificar
    @PutMapping("/{id}")
    public ResponseEntity<Factura> actualizar(@PathVariable Long id, @RequestBody Factura cambios) {
        return repository.findById(id)
                .map(existente -> {
                    existente.setNumero(cambios.getNumero());
                    existente.setMonto(cambios.getMonto());
                    existente.setClienteId(cambios.getClienteId());
                    existente.setFechaEmision(cambios.getFechaEmision());
                    return ResponseEntity.ok(repository.save(existente));
                })
                .orElseGet(() -> ResponseEntity.notFound().build());
    }

    // DELETE /facturas/{id} -> baja
    @DeleteMapping("/{id}")
    public ResponseEntity<Void> borrar(@PathVariable Long id) {
        if (!repository.existsById(id)) {
            return ResponseEntity.notFound().build();
        }
        repository.deleteById(id);
        return ResponseEntity.noContent().build();
    }
}
