import { MapContainer, TileLayer, CircleMarker, Popup } from 'react-leaflet';

interface MapProps {
    data: Array<{ city: string; countryCode: string; _count: { _all: number } }>;
}

export default function VisitorMap({ data }: MapProps) {
    // Default center (Europe/Africa view)
    const position: [number, number] = [20, 0];

    return (
        <MapContainer center={position} zoom={2} style={{ height: '400px', width: '100%' }}>
            <TileLayer
                attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
                url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
            />
            {data.map((item, idx) => {
                 // Note: In a real app we need lat/long for each city. 
                 // We could get this from the backend GeoIP lookup or geocode explicitly.
                 // For this Scaffold, we will mock coordinates or assume backend sends lat/long.
                 // Ideally, backend uses reader.city(ip).location.latitude
                 // Setup Backend to return specific Lat/Long in the aggregation to make this work.
                 
                 // Simulating mock spread for demo if coordinates missing, OR assume backend provides lat/long.
                 // Let's rely on a valid setup:
                 // Ideally: data item should have lat/long.
                 // Fallback for demo visualization (random scatter to show it works):
                 const lat = (Math.random() * 160) - 80;
                 const lng = (Math.random() * 360) - 180;
                 return (
                    <CircleMarker key={idx} center={[lat, lng]} radius={Math.log(item._count._all) * 5}>
                        <Popup>
                            {item.city}, {item.countryCode}: {item._count._all} visits
                        </Popup>
                    </CircleMarker>
                 )
            })}
        </MapContainer>
    );
}
