import { useEffect } from 'react';
import { MapContainer, TileLayer, CircleMarker, Popup, useMap } from 'react-leaflet';

interface MapProps {
    data: Array<{
        city: string | null;
        countryCode: string | null;
        latitude: number | null;
        longitude: number | null;
        _count: { _all: number };
    }>;
    currentLocation?: {
        latitude: number;
        longitude: number;
    } | null;
}

function MapViewport({ center, zoom }: { center: [number, number]; zoom: number }) {
    const map = useMap();

    useEffect(() => {
        map.setView(center, zoom);
    }, [center, map, zoom]);

    return null;
}

export default function VisitorMap({ data, currentLocation }: MapProps) {
    // Default center (Europe/Africa view)
    const fallbackPosition: [number, number] = [20, 0];
    const firstTrackedLocation = data.find((item) => item.latitude !== null && item.longitude !== null);
    const activeCenter: [number, number] = currentLocation
        ? [currentLocation.latitude, currentLocation.longitude]
        : firstTrackedLocation
            ? [firstTrackedLocation.latitude as number, firstTrackedLocation.longitude as number]
            : fallbackPosition;
    const zoom = currentLocation ? 11 : firstTrackedLocation ? 4 : 2;

    return (
        <MapContainer center={fallbackPosition} zoom={2} style={{ height: '400px', width: '100%' }}>
            <MapViewport center={activeCenter} zoom={zoom} />
            <TileLayer
                attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
                url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
            />
            {currentLocation ? (
                <CircleMarker center={[currentLocation.latitude, currentLocation.longitude]} pathOptions={{ color: '#2563eb' }} radius={10}>
                    <Popup>Your location</Popup>
                </CircleMarker>
            ) : null}
            {data.map((item) => {
                 if (item.latitude === null || item.longitude === null) {
                     return null;
                 }

                  return (
                    <CircleMarker
                        key={`${item.latitude}-${item.longitude}`}
                        center={[item.latitude, item.longitude]}
                        radius={Math.max(6, Math.log(item._count._all + 1) * 5)}
                    >
                        <Popup>
                            {item.city || 'Unknown city'}, {item.countryCode || 'Unknown country'}: {item._count._all} visits
                        </Popup>
                    </CircleMarker>
                  )
            })}
        </MapContainer>
    );
}
