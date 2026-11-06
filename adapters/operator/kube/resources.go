package kube

import (
	"context"

	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/controller/controllerutil"
)

const payloadKey = "payload"

type OwnedConfigMap struct {
	Name    string
	Payload string
}

type ConfigMapPort interface {
	ListOwned(ctx context.Context, owner client.Object, desiredNames []string) (owned []OwnedConfigMap, foreign []string, err error)
	Upsert(ctx context.Context, owner client.Object, name, payload string) error
	Delete(ctx context.Context, owner client.Object, name string) error
}

type ConfigMapAdapter struct {
	client client.Client
	scheme *runtime.Scheme
	label  string
}

func NewConfigMapAdapter(c client.Client, scheme *runtime.Scheme, label string) ConfigMapAdapter {
	return ConfigMapAdapter{client: c, scheme: scheme, label: label}
}

func (a ConfigMapAdapter) ListOwned(ctx context.Context, owner client.Object, desiredNames []string) ([]OwnedConfigMap, []string, error) {
	var list corev1.ConfigMapList
	if err := a.client.List(ctx, &list, client.InNamespace(owner.GetNamespace())); err != nil {
		return nil, nil, err
	}
	desired := make(map[string]bool, len(desiredNames))
	for _, name := range desiredNames {
		desired[name] = true
	}

	var owned []OwnedConfigMap
	var foreign []string
	for i := range list.Items {
		cm := &list.Items[i]
		switch {
		case ownedBy(cm, owner):
			owned = append(owned, OwnedConfigMap{Name: cm.Name, Payload: cm.Data[payloadKey]})
		case desired[cm.Name]:
			foreign = append(foreign, cm.Name)
		default:
		}
	}
	return owned, foreign, nil
}

func (a ConfigMapAdapter) Upsert(ctx context.Context, owner client.Object, name, payload string) error {
	var cm corev1.ConfigMap
	err := a.client.Get(ctx, client.ObjectKey{Namespace: owner.GetNamespace(), Name: name}, &cm)
	if apierrors.IsNotFound(err) {
		desired := &corev1.ConfigMap{
			ObjectMeta: metav1.ObjectMeta{
				Name:      name,
				Namespace: owner.GetNamespace(),
				Labels:    map[string]string{a.label: owner.GetName()},
			},
			Data: map[string]string{payloadKey: payload},
		}
		if refErr := controllerutil.SetControllerReference(owner, desired, a.scheme); refErr != nil {
			return refErr
		}
		return a.client.Create(ctx, desired)
	}
	if err != nil {
		return err
	}
	if !ownedBy(&cm, owner) {
		return apierrors.NewAlreadyExists(corev1.Resource("configmaps"), name)
	}
	if cm.Data[payloadKey] == payload {
		return nil
	}
	if cm.Data == nil {
		cm.Data = map[string]string{}
	}
	cm.Data[payloadKey] = payload
	return a.client.Update(ctx, &cm)
}

func (a ConfigMapAdapter) Delete(ctx context.Context, owner client.Object, name string) error {
	var cm corev1.ConfigMap
	err := a.client.Get(ctx, client.ObjectKey{Namespace: owner.GetNamespace(), Name: name}, &cm)
	if apierrors.IsNotFound(err) {
		return nil
	}
	if err != nil {
		return err
	}
	if !ownedBy(&cm, owner) {
		return nil // never delete a foreign object
	}
	return client.IgnoreNotFound(a.client.Delete(ctx, &cm))
}

func ownedBy(object metav1.Object, owner client.Object) bool {
	ref := metav1.GetControllerOf(object)
	return ref != nil && ref.UID == owner.GetUID()
}
