package v1alpha1

import (
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

const NoteFinalizer = "sample.diene.atomi.cloud/note-finalizer"

type NoteSpec struct {
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:MinLength=1
	// +kubebuilder:validation:MaxLength=253
	Title string `json:"title"`

	// +kubebuilder:validation:Required
	// +kubebuilder:validation:MinLength=1
	Body string `json:"body"`

	// +kubebuilder:validation:Required
	// +kubebuilder:validation:Enum=personal;work;archive
	Category string `json:"category"`

	// +kubebuilder:validation:Minimum=0
	// +kubebuilder:validation:Maximum=50
	// +kubebuilder:default=1
	Replicas int32 `json:"replicas,omitempty"`
}

type NoteStatus struct {
	// +optional
	// +listType=map
	// +listMapKey=type
	Conditions []metav1.Condition `json:"conditions,omitempty"`

	// +optional
	ObservedGeneration int64 `json:"observedGeneration,omitempty"`

	// +optional
	OwnedConfigMaps int32 `json:"ownedConfigMaps,omitempty"`

	// LedgerRef is a ledger coordinate, never a secret value.
	// +optional
	LedgerRef string `json:"ledgerRef,omitempty"`
}

// +kubebuilder:object:root=true
// +kubebuilder:subresource:status
// +kubebuilder:resource:scope=Namespaced,shortName=nt
// +kubebuilder:printcolumn:name="Category",type=string,JSONPath=`.spec.category`
// +kubebuilder:printcolumn:name="Copies",type=integer,JSONPath=`.status.ownedConfigMaps`
// +kubebuilder:printcolumn:name="Ready",type=string,JSONPath=`.status.conditions[?(@.type=="Ready")].status`
// +kubebuilder:printcolumn:name="Age",type=date,JSONPath=`.metadata.creationTimestamp`
type Note struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec   NoteSpec   `json:"spec,omitempty"`
	Status NoteStatus `json:"status,omitempty"`
}

// +kubebuilder:object:root=true
type NoteList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []Note `json:"items"`
}

var _ = SchemeBuilder.Register(&Note{}, &NoteList{})
